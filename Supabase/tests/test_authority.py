"""Pruebas reales de PostgreSQL. auth.uid se simula en bootstrap; no prueban GoTrue ni dos dispositivos."""
import copy
import json
import os
import subprocess
import unittest
import uuid

CONTAINER = os.environ.get('HOGAR_TEST_CONTAINER', 'hogar-postgres-tests')
DOCKER_ENV = os.environ.copy()
for selector in ('DOCKER_HOST', 'DOCKER_CONTEXT', 'DOCKER_TLS', 'DOCKER_TLS_VERIFY', 'DOCKER_CERT_PATH'):
    DOCKER_ENV.pop(selector, None)


def literal(value):
    if value is None:
        return 'null'
    if isinstance(value, bool):
        return 'true' if value else 'false'
    if isinstance(value, int):
        return str(value)
    if isinstance(value, (dict, list)):
        return "'" + json.dumps(value, ensure_ascii=False).replace("'", "''") + "'::jsonb"
    return "'" + str(value).replace("'", "''") + "'"


def sql(command, actor=None, role=None):
    prefix = ''
    if role or actor:
        prefix = 'set role ' + (role or 'authenticated') + '; '
    if actor:
        prefix += 'set request.jwt.claim.sub=' + literal(actor) + '; '
    return subprocess.run(['docker', '--host=unix:///var/run/docker.sock', 'exec', '-i', CONTAINER,
                           'psql', '-XqAt', '-v', 'ON_ERROR_STOP=1', '-v', 'VERBOSITY=verbose', '-U', 'postgres'],
                          input=prefix + command, capture_output=True, text=True, env=DOCKER_ENV)


def rpc(name, values, actor=None, role=None):
    return sql('select public.' + name + '(' + ','.join(literal(v) for v in values) + ');', actor, role)


class AuthorityTests(unittest.TestCase):
    def setUp(self):
        self.admin, self.member, self.stranger, self.unconfirmed = [str(uuid.uuid4()) for _ in range(4)]
        self.email = self.member + '@example.invalid'
        for actor in (self.admin, self.member, self.stranger, self.unconfirmed):
            confirmed = 'null' if actor == self.unconfirmed else 'now()'
            result = sql('insert into auth.users values(' + literal(actor) + ',' + literal(actor + '@example.invalid') + ',' + confirmed + ');')
            self.assertEqual(result.returncode, 0, result.stderr)
        created = self.ok('family_create', ['Casa', 'Ana'], self.admin)
        self.home = created['household']['id']
        self.account = str(uuid.uuid4())

    def ok(self, method, params, actor):
        result = rpc(method, params, actor)
        self.assertEqual(result.returncode, 0, result.stderr)
        return json.loads(result.stdout.strip())

    def denied(self, method, params, actor, code):
        result = rpc(method, params, actor)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn(code, result.stderr)

    def get(self, actor=None):
        return self.ok('family_get', [self.home], actor or self.admin)

    def commit(self, snapshot, actor=None, operation=None):
        return self.ok('family_commit', [self.home, operation or str(uuid.uuid4()), snapshot['revision'], snapshot['household']], actor or self.admin)

    def invite_member(self):
        invite = self.ok('family_invite', [self.home, self.email], self.admin)
        return self.ok('family_accept', [invite['token'], 'Luis'], self.member), invite

    def with_account(self):
        snapshot = self.get()
        snapshot['household']['accounts'] = [{'id': self.account, 'name': 'Banco', 'kind': 'Banco', 'opening': {'cents': 100000}}]
        self.commit(snapshot)
        return self.get()

    def entry(self, author=None, cents=1000, kind='Gasto'):
        return {'id': str(uuid.uuid4()), 'authorID': author or self.admin, 'memberID': author or self.admin,
                'accountID': self.account, 'kind': kind, 'amount': {'cents': cents}, 'date': 0,
                'category': 'Alimentación', 'title': 'Compra', 'notes': '', 'tags': [], 'revision': 0, 'deleted': False}

    def test_unauthenticated_unconfirmed_and_stranger_cannot_read(self):
        result = rpc('family_get', [self.home], role='anon')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('42501', result.stderr)
        self.denied('family_get', [self.home], self.stranger, 'PT403')
        self.denied('family_create', ['Casa', 'Sin confirmar'], self.unconfirmed, 'email_unconfirmed')
        result = sql('select * from hogar_private.households;', self.admin)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('42501', result.stderr)

    def test_invitation_binds_confirmed_email_and_retry_is_safe(self):
        invitation = self.ok('family_invite', [self.home, self.email], self.admin)
        self.denied('family_accept', [invitation['token'], 'Otro'], self.stranger, 'invalid_invite')
        accepted = self.ok('family_accept', [invitation['token'], 'Luis'], self.member)
        retried = self.ok('family_accept', [invitation['token'], 'Luis'], self.member)
        self.assertEqual(accepted, retried)
        self.assertEqual(len(accepted['household']['members']), 2)
        self.assertEqual(len(self.ok('family_list', [], self.member)), 1)

    def test_cancelled_and_expired_invites_reject(self):
        invitation = self.ok('family_invite', [self.home, self.email], self.admin)
        self.ok('family_cancel_invite', [self.home, invitation['id']], self.admin)
        self.denied('family_accept', [invitation['token'], 'Luis'], self.member, 'invalid_invite')
        invitation = self.ok('family_invite', [self.home, self.email], self.admin)
        result = sql('update hogar_private.invites set expires_at=now()-interval \'1 day\' where id=' + literal(invitation['id']) + ';')
        self.assertEqual(result.returncode, 0)
        self.denied('family_accept', [invitation['token'], 'Luis'], self.member, 'invalid_invite')

    def test_member_cannot_invite_promote_or_manage_configuration(self):
        self.invite_member()
        self.denied('family_invite', [self.home, 'otro@example.invalid'], self.member, 'admin_required')
        self.denied('family_membership', [self.home, self.member, 'admin', True], self.member, 'admin_required')
        snapshot = self.get(self.member)
        snapshot['household']['name'] = 'Usurpado'
        self.denied('family_commit', [self.home, str(uuid.uuid4()), snapshot['revision'], snapshot['household']], self.member, 'admin_required')

    def test_author_not_attributed_member_controls_edit(self):
        self.invite_member()
        snapshot = self.with_account()
        value = self.entry(); value['memberID'] = self.member
        snapshot['household']['entries'] = [value]
        self.commit(snapshot)
        snapshot = self.get(self.member)
        snapshot['household']['entries'][0]['title'] = 'Ajeno'; snapshot['household']['entries'][0]['revision'] += 1
        self.denied('family_commit', [self.home, str(uuid.uuid4()), snapshot['revision'], snapshot['household']], self.member, 'author_required')
        self.assertEqual(self.get()['household']['entries'][0]['title'], 'Compra')

    def test_member_creates_own_and_admin_can_edit_without_changing_author(self):
        self.invite_member(); self.with_account()
        snapshot = self.get(self.member); snapshot['household']['entries'] = [self.entry(self.member)]
        self.commit(snapshot, self.member)
        snapshot = self.get(); snapshot['household']['entries'][0]['title'] = 'Corregido'; snapshot['household']['entries'][0]['revision'] = 1
        self.commit(snapshot)
        self.assertEqual(self.get()['household']['entries'][0]['authorID'], self.member)
        snapshot = self.get(); snapshot['household']['entries'][0]['authorID'] = self.admin; snapshot['household']['entries'][0]['revision'] = 2
        self.denied('family_commit', [self.home, str(uuid.uuid4()), snapshot['revision'], snapshot['household']], self.admin, 'entry_conflict')

    def test_forged_member_list_does_not_grant_admin(self):
        self.invite_member(); self.with_account()
        snapshot = self.get(self.member)
        for m in snapshot['household']['members']:
            if m['id'] == self.member: m['role'] = 'admin'
        snapshot['household']['entries'] = [self.entry(self.member)]
        self.commit(snapshot, self.member)
        self.assertEqual(next(m['role'] for m in self.get()['household']['members'] if m['id'] == self.member), 'member')

    def test_conflict_and_idempotent_receipt_after_lost_ack(self):
        snapshot = self.with_account(); operation = str(uuid.uuid4())
        snapshot['household']['entries'] = [self.entry()]
        receipt = self.commit(snapshot, operation=operation)
        self.assertEqual(receipt, self.commit(snapshot, operation=operation))
        self.assertEqual(len(self.get()['household']['entries']), 1)
        self.denied('family_commit', [self.home, str(uuid.uuid4()), snapshot['revision'], snapshot['household']], self.admin, 'conflict')
        snapshot['household']['entries'][0]['title'] = 'Cuerpo diferente'
        self.denied('family_commit', [self.home, operation, snapshot['revision'], snapshot['household']], self.admin, 'operation_reused')

    def test_tombstone_and_no_resurrection(self):
        snapshot = self.with_account(); snapshot['household']['entries'] = [self.entry()]; self.commit(snapshot)
        snapshot = self.get(); old = copy.deepcopy(snapshot)
        snapshot['household']['entries'] = []
        self.denied('family_commit', [self.home, str(uuid.uuid4()), snapshot['revision'], snapshot['household']], self.admin, 'tombstone_required')
        old['household']['entries'][0]['deleted'] = True; old['household']['entries'][0]['revision'] = 1; self.commit(old)
        old = self.get(); old['household']['entries'][0]['deleted'] = False; old['household']['entries'][0]['revision'] = 2
        self.denied('family_commit', [self.home, str(uuid.uuid4()), old['revision'], old['household']], self.admin, 'entry_conflict')

    def test_financial_scenario_and_transfer_neutrality(self):
        snapshot = self.with_account()
        cash = str(uuid.uuid4())
        snapshot['household']['accounts'].append({'id': cash, 'name': 'Efectivo', 'kind': 'Efectivo', 'opening': {'cents': 0}})
        snapshot['household']['entries'] = [self.entry(cents=200000, kind='Ingreso'), self.entry(cents=50000)]
        transfer = self.entry(cents=30000, kind='Transferencia'); transfer['destinationID'] = cash
        snapshot['household']['entries'].append(transfer)
        snapshot['household']['goals'] = [{'id': str(uuid.uuid4()), 'name': 'Meta', 'target': {'cents': 100000}, 'reserved': {'cents': 60000}, 'due': 0}]
        self.commit(snapshot)
        stored = self.get()['household']
        total = sum(a['opening']['cents'] for a in stored['accounts']) + sum(e['amount']['cents'] * (1 if e['kind'] == 'Ingreso' else -1 if e['kind'] == 'Gasto' else 0) for e in stored['entries'])
        self.assertEqual(total, 250000)
        self.assertEqual(total - stored['goals'][0]['reserved']['cents'], 190000)
        self.assertEqual(sum(e['amount']['cents'] for e in stored['entries'] if e['kind'] == 'Gasto'), 50000)

    def test_invalid_money_and_references_roll_back(self):
        snapshot = self.with_account()
        for amount in (0, -1, 1.25, 9000000000001):
            changed = copy.deepcopy(snapshot); changed['household']['entries'] = [self.entry(cents=amount)]
            self.denied('family_commit', [self.home, str(uuid.uuid4()), changed['revision'], changed['household']], self.admin, 'PT422')
        changed = copy.deepcopy(snapshot); value = self.entry(); value['accountID'] = str(uuid.uuid4()); changed['household']['entries'] = [value]
        self.denied('family_commit', [self.home, str(uuid.uuid4()), changed['revision'], changed['household']], self.admin, 'invalid_entry')
        self.assertEqual(self.get(), snapshot)

    def test_reservations_serialize_and_later_expense_is_preserved(self):
        snapshot = self.with_account()
        snapshot['household']['goals'] = [{'id': str(uuid.uuid4()), 'name': 'Meta', 'target': {'cents': 200000}, 'reserved': {'cents': 90000}, 'due': 0}]
        self.commit(snapshot)
        stale = copy.deepcopy(snapshot)
        self.denied('family_commit', [self.home, str(uuid.uuid4()), stale['revision'], stale['household']], self.admin, 'conflict')
        snapshot = self.get(); snapshot['household']['goals'][0]['reserved']['cents'] = 100001
        self.denied('family_commit', [self.home, str(uuid.uuid4()), snapshot['revision'], snapshot['household']], self.admin, 'insufficient_unreserved')
        snapshot = self.get(); snapshot['household']['entries'] = [self.entry(cents=50000)]
        self.commit(snapshot)
        self.assertEqual(self.get()['household']['goals'][0]['reserved']['cents'], 90000)

    def test_revocation_blocks_read_write_and_ack_replay(self):
        self.invite_member(); self.with_account()
        snapshot = self.get(self.member); snapshot['household']['entries'] = [self.entry(self.member)]
        operation = str(uuid.uuid4()); self.commit(snapshot, self.member, operation)
        self.ok('family_membership', [self.home, self.member, 'member', False], self.admin)
        self.denied('family_get', [self.home], self.member, 'access_revoked')
        self.denied('family_commit', [self.home, operation, snapshot['revision'], snapshot['household']], self.member, 'access_revoked')

    def test_last_admin_cannot_leave_and_member_can_leave(self):
        self.invite_member()
        self.denied('family_membership', [self.home, self.admin, 'admin', False], self.admin, 'last_admin')
        self.ok('family_membership', [self.home, self.member, 'member', False], self.member)
        self.denied('family_get', [self.home], self.member, 'access_revoked')

    def test_budget_history_and_tag_validation(self):
        snapshot = self.with_account()
        snapshot['household']['budgets'] = [{'id': str(uuid.uuid4()), 'month': {'year': 2026, 'month': m}, 'category': 'Alimentación', 'limit': {'cents': m * 1000}} for m in (1, 2)]
        self.commit(snapshot)
        snapshot = self.get(); snapshot['household']['budgets'][1]['limit']['cents'] = 90000; self.commit(snapshot)
        self.assertEqual(self.get()['household']['budgets'][0]['limit']['cents'], 1000)
        snapshot = self.get(); value = self.entry(); value['tags'] = ['Educación', 'educacion']; snapshot['household']['entries'] = [value]
        self.denied('family_commit', [self.home, str(uuid.uuid4()), snapshot['revision'], snapshot['household']], self.admin, 'invalid_tags')

    def test_create_retries_use_the_same_home_without_duplicates(self):
        home = str(uuid.uuid4())
        first = self.ok('family_create', ['Otra casa', 'Ana', home], self.admin)
        second = self.ok('family_create', ['Otra casa', 'Ana', home], self.admin)
        self.assertEqual(first, second)
        self.denied('family_create', ['Usurpar', 'Otro', home], self.stranger, 'PT403')

    def test_concurrent_reservations_cannot_overbook(self):
        from concurrent.futures import ThreadPoolExecutor
        self.invite_member(); self.with_account()
        self.ok('family_membership', [self.home, self.member, 'admin', True], self.admin)
        snapshot = self.get()
        choices = []
        for _ in range(2):
            proposal = copy.deepcopy(snapshot)
            proposal['household']['goals'] = [{'id': str(uuid.uuid4()), 'name': 'Meta', 'target': {'cents': 100000}, 'reserved': {'cents': 60000}, 'due': 0}]
            choices.append(proposal)
        def send(index):
            return rpc('family_commit', [self.home, str(uuid.uuid4()), choices[index]['revision'], choices[index]['household']], [self.admin,self.member][index])
        with ThreadPoolExecutor(max_workers=2) as pool:
            outcomes = list(pool.map(send, (0,1)))
        self.assertEqual(sum(r.returncode == 0 for r in outcomes), 1)
        self.assertTrue(any('PT409' in r.stderr for r in outcomes))
        stored = self.get()['household']
        self.assertEqual(sum(g['reserved']['cents'] for g in stored['goals']), 60000)

    def test_json_string_numbers_and_unknown_fields_do_not_poison_readers(self):
        snapshot = self.with_account()
        for change in ('schema','revision','month','unknown'):
            candidate = copy.deepcopy(snapshot)
            if change == 'schema': candidate['household']['schema'] = '1'
            elif change == 'revision':
                value = self.entry(); value['revision'] = '0'; candidate['household']['entries'] = [value]
            elif change == 'month':
                candidate['household']['budgets'] = [{'id': str(uuid.uuid4()), 'month': {'year': '2026', 'month': 1}, 'category': 'Salud', 'limit': {'cents': 10}}]
            else:
                value = self.entry(); value['unknown'] = 'not part of the financial model'; candidate['household']['entries'] = [value]
            self.denied('family_commit', [self.home, str(uuid.uuid4()), candidate['revision'], candidate['household']], self.admin, 'PT422')
        self.assertEqual(self.get(), snapshot)

    def test_rls_still_denies_direct_rows_if_a_select_grant_is_added(self):
        result = sql('begin; grant usage on schema hogar_private to authenticated; grant select on hogar_private.households to authenticated; set role authenticated; set request.jwt.claim.sub=' + literal(self.admin) + '; select count(*) from hogar_private.households; rollback;')
        self.assertEqual(result.returncode,0,result.stderr)
        self.assertEqual(result.stdout.strip(),'0')

    def test_reinvitation_does_not_restore_old_admin_or_reuse_revoked_access(self):
        _, invitation = self.invite_member()
        self.ok('family_membership', [self.home,self.member,'admin',True], self.admin)
        self.ok('family_membership', [self.home,self.member,'admin',False], self.admin)
        self.denied('family_accept', [invitation['token'],'Luis'], self.member, 'access_revoked')
        new = self.ok('family_invite', [self.home,self.email], self.admin)
        snapshot = self.ok('family_accept', [new['token'],'Luis'], self.member)
        self.assertEqual(next(m['role'] for m in snapshot['household']['members'] if m['id']==self.member),'member')

    def test_imported_unknown_authors_require_admin(self):
        self.invite_member(); self.with_account()
        snapshot = self.get(self.member)
        value = self.entry(self.member); value.pop('authorID')
        snapshot['household']['entries'] = [value]
        self.denied('family_commit', [self.home,str(uuid.uuid4()),snapshot['revision'],snapshot['household']], self.member, 'author_required')
        self.commit(snapshot,self.admin)
        self.assertNotIn('authorID',self.get()['household']['entries'][0])

    def test_admin_can_delete_historical_entry_after_member_revocation(self):
        self.invite_member(); self.with_account()
        snapshot = self.get(self.member)
        snapshot['household']['entries'] = [self.entry(self.member)]
        self.commit(snapshot,self.member)
        self.ok('family_membership',[self.home,self.member,'member',False],self.admin)
        snapshot = self.get()
        snapshot['household']['entries'][0]['revision'] = 1
        snapshot['household']['entries'][0]['deleted'] = True
        self.commit(snapshot)
        self.assertTrue(self.get()['household']['entries'][0]['deleted'])

    def test_unicode_whitespace_and_control_tags_cannot_poison_readers(self):
        self.denied('family_create', ['Casa','\t\u00a0'], self.admin, 'invalid_data')
        snapshot = self.with_account()
        for tag in ('\u00a0Etiqueta','Texto\u200binvisible'):
            proposed = copy.deepcopy(snapshot)
            value = self.entry(); value['tags'] = [tag]
            proposed['household']['entries'] = [value]
            self.denied('family_commit',[self.home,str(uuid.uuid4()),proposed['revision'],proposed['household']], self.admin,'invalid_tags')


if __name__ == '__main__':
    unittest.main(verbosity=2)
