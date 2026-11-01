"""Fuente del diseño. Genera SVG y un importador local de Figma con capas/textos nativos."""
from pathlib import Path
import json
import html

ROOT = Path(__file__).parent
ICONS = {
 'house': '<path d="M3 11 12 3l9 8M6 10v11h12V10M10 21v-7h4v7"/>',
 'chart': '<path d="M4 20V10m8 10V4m8 16v-7"/>',
 'arrows': '<path d="M8 3v18m-4-4 4 4 4-4m4 4V3m-4 4 4-4 4 4"/>',
 'wallet': '<rect x="3" y="5" width="18" height="15" rx="3"/><path d="M3 9h18m-5 4h5v4h-5z"/>',
 'target': '<circle cx="12" cy="12" r="9"/><circle cx="12" cy="12" r="5"/><circle cx="12" cy="12" r="1"/>',
 'plus': '<path d="M12 5v14M5 12h14"/>',
 'scan': '<path d="M8 3H3v5m13-5h5v5M3 16v5h5m13-5v5h-5M7 9h10M7 13h7M7 17h4"/>',
 'left': '<path d="m14 6-6 6 6 6"/>',
 'right': '<path d="m9 6 6 6-6 6"/>',
 'down': '<path d="M17 7 7 17m0-9v9h9"/>',
 'up': '<path d="M7 17 17 7m0 9V7H8"/>',
 'equal': '<path d="M5 9h14M5 15h14"/>',
 'wifi': '<path d="M3 8a15 15 0 0 1 18 0M6 12a10 10 0 0 1 12 0m-9 4a5 5 0 0 1 6 0"/><circle cx="12" cy="20" r=".5"/>',
 'bars': '<path d="M4 20v-4m5 4V12m5 8V8m5 12V4"/>',
 'battery': '<rect x="2" y="6" width="17" height="12" rx="3"/><path d="M22 10v4M6 10h9v4H6z"/>',
}
LIGHT = dict(bg='#F5F7F6',surface='#FFFFFF',ink='#182A24',muted='#697A72',line='#DFE7E2',accent='#176B55',soft='#E7F2EC',buttonInk='#FFFFFF',positive='#176B55',expense='#9B4C39')
DARK = dict(bg='#111A17',surface='#1C2822',ink='#F0F5F2',muted='#A4B6AC',line='#33453B',accent='#92DDB8',soft='#253F32',buttonInk='#11291D',positive='#92DDB8',expense='#E8AC98')


def frame(name, x, y, w, h, fill, radius=0, stroke=None, children=None):
    return dict(type='frame',name=name,x=x,y=y,width=w,height=h,fill=fill,radius=radius,stroke=stroke,children=children or [])


def text(name, value, x, y, w, h, size, color, weight='Regular', align='LEFT'):
    return dict(type='text',name=name,text=value,x=x,y=y,width=w,height=h,size=size,color=color,weight=weight,align=align)


def icon(name, glyph, x, y, color, size=24):
    svg = f'<svg xmlns="http://www.w3.org/2000/svg" width="{size}" height="{size}" viewBox="0 0 24 24"><g fill="none" stroke="{color}" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round">{ICONS[glyph]}</g></svg>'
    return dict(type='icon',name=name,x=x,y=y,width=size,height=size,svg=svg)


def mobile(p, theme):
    n = []
    n += [text('Hora','9:41',26,14,70,22,14,p['ink'],'Semi Bold'), icon('Cobertura','bars',286,14,p['ink'],18), icon('Wifi','wifi',310,14,p['ink'],18), icon('Batería','battery',334,13,p['ink'],21)]
    n += [text('Marca','HOGAR FINANZAS',22,62,260,18,10,p['muted'],'Semi Bold'),text('Título','Resumen',22,89,280,42,30,p['ink'],'Bold')]
    n += [frame('Perfil',330,82,40,40,p['soft'],20,children=[text('Iniciales','HF',0,10,40,22,13,p['accent'],'Bold','CENTER')])]
    n += [icon('Mes anterior','left',20,150,p['muted'],20),text('Mes','Noviembre de 2026',56,146,278,28,16,p['ink'],'Medium','CENTER'),icon('Mes siguiente','right',350,150,p['muted'],20)]
    n += [frame('Saldo · tarjeta principal',20,194,350,190,p['surface'],22,p['line'],[
        text('Título del saldo','Saldo registrado total',20,18,310,22,13,p['muted'],'Medium'),
        text('Saldo','2.500,00 €',20,46,310,48,38,p['ink'],'Semi Bold'),
        frame('Separador',20,104,310,1,p['line']),
        text('Etiqueta reserva','Reservado',20,118,145,18,11,p['muted']),text('Importe reserva','600,00 €',20,139,145,26,18,p['ink'],'Semi Bold'),
        text('Etiqueta sin reservar','Sin reservar',184,118,146,18,11,p['muted']),text('Importe sin reservar','1.900,00 €',184,139,146,26,18,p['positive'],'Semi Bold'),
        text('Aclaración','Sin reservar no descuenta recibos futuros.',20,171,310,14,10,p['muted'])])]
    for x,label,value,glyph,color in [(20,'Ingresos','2.000,00 €','down',p['positive']),(140,'Gastos','500,00 €','up',p['expense']),(260,'Resultado','1.500,00 €','equal',p['ink'])]:
        n += [frame('Mes · '+label,x,402,110,104,p['surface'],16,p['line'],[icon('Icono '+label,glyph,12,12,color,18),text('Etiqueta '+label,label,12,38,86,18,11,p['muted']),text('Importe '+label,value,12,61,96,25,16,color,'Semi Bold')])]
    n += [frame('Acción · registrar gasto',20,530,350,54,p['accent'],16,children=[icon('Más','plus',98,15,p['buttonInk'],22),text('Texto registrar','Registrar gasto',130,15,200,25,16,p['buttonInk'],'Semi Bold')])]
    n += [frame('Acción · aviso bancario',20,596,350,46,p['surface'],14,p['line'],[icon('Escanear aviso','scan',82,12,p['accent'],22),text('Texto aviso','Desde aviso bancario',114,13,220,23,14,p['ink'],'Medium')])]
    n += [frame('Detalle cerrado',20,658,350,48,p['surface'],14,p['line'],[text('Etiqueta detalle','Detalle y evolución',16,14,270,22,14,p['ink'],'Medium'),icon('Abrir detalle','right',310,14,p['muted'],20)])]
    # Barra propia del sistema, sin mensajes ni capas superpuestas sobre los botones.
    bar=[]
    labels=[('Resumen','chart'),('Movimientos','arrows'),('Cuentas','wallet'),('Planes','target'),('Hogar','house')]
    for i,(label,glyph) in enumerate(labels):
        c=p['accent'] if i==0 else p['muted']
        if i==0: bar.append(frame('Selección Resumen',16,11,46,30,p['soft'],12))
        bar += [icon('Navegación · '+label,glyph,i*78+27,14,c,24),text('Pestaña '+label,label,i*78,47,78,18,10,c,'Medium','CENTER')]
    bar += [frame('Indicador de inicio',128,82,134,4,p['ink'],2)]
    n += [frame('Navegación inferior · despejada',0,750,390,94,p['surface'],0,p['line'],bar)]
    return frame('Dashboard · iPhone · '+theme,0,0,390,844,p['bg'],children=n)


def desktop(p,theme):
    sidebar=[icon('Marca icono','house',24,32,p['accent'],28),text('Marca','Hogar Finanzas',64,35,166,28,18,p['ink'],'Semi Bold'),text('Sección','MI HOGAR',24,92,190,20,10,p['muted'],'Semi Bold')]
    for i,(label,glyph) in enumerate([('Resumen','chart'),('Movimientos','arrows'),('Cuentas','wallet'),('Planificación','target'),('Hogar y copias','house')]):
        y=127+i*54
        if i==0: sidebar += [frame('Selección',16,y,208,44,p['soft'],12)]
        color=p['accent'] if i==0 else p['muted']
        sidebar += [icon('Menú '+label,glyph,30,y+10,color),text('Sección '+label,label,66,y+11,150,26,14,color,'Semi Bold' if i==0 else 'Medium')]
    sidebar += [frame('Separador perfil',24,708,192,1,p['line']),text('Hogar activo','Mi hogar',28,732,180,22,14,p['ink'],'Medium'),text('Perfil local','Preferencias y miembros',28,758,190,20,11,p['muted'])]
    n=[frame('Barra lateral',0,0,240,800,p['surface'],0,p['line'],sidebar)]
    n += [text('Título','Resumen',272,44,700,52,34,p['ink'],'Bold'),icon('Mes anterior','left',274,116,p['muted'],20),text('Mes','Noviembre de 2026',308,112,232,28,16,p['ink'],'Medium'),icon('Mes siguiente','right',542,116,p['muted'],20)]
    n += [frame('Saldo · tarjeta principal',272,166,976,196,p['surface'],24,p['line'],[
        text('Título saldo','Saldo registrado total',28,24,440,24,14,p['muted'],'Medium'),text('Saldo','2.500,00 €',28,63,450,64,46,p['ink'],'Semi Bold'),
        text('Aclaración saldo','Todos los movimientos registrados, sin conexión bancaria.',28,145,460,24,12,p['muted']),
        frame('Separador',524,32,1,132,p['line']),text('Etiqueta reserva','Reservado para metas',558,38,360,22,13,p['muted']),text('Reserva','600,00 €',558,66,360,32,25,p['ink'],'Semi Bold'),
        text('Etiqueta sin reservar','Saldo sin reservar',558,110,360,22,13,p['muted']),text('Sin reservar','1.900,00 €',558,138,360,36,25,p['positive'],'Semi Bold')])]
    for x,label,value,glyph,color in [(272,'Ingresos del mes','2.000,00 €','down',p['positive']),(608,'Gastos del mes','500,00 €','up',p['expense']),(944,'Resultado del mes','1.500,00 €','equal',p['ink'])]:
        n += [frame('Mes · '+label,x,386,304,128,p['surface'],18,p['line'],[icon('Icono '+label,glyph,20,20,color,22),text('Etiqueta '+label,label,56,20,228,24,13,p['muted'],'Medium'),text('Importe '+label,value,20,64,264,44,30,color,'Semi Bold')])]
    n += [text('Aclaración reservas','El saldo sin reservar no descuenta recibos ni compromisos futuros.',272,532,976,22,12,p['muted'])]
    n += [frame('Acción · registrar',272,576,268,52,p['accent'],14,children=[icon('Más','plus',26,590,p['buttonInk'],24),text('Texto registrar','Registrar gasto',64,15,184,26,16,p['buttonInk'],'Semi Bold')])]
    # Corregir coordenadas locales del icono dentro del botón.
    n[-1]['children'][0]['x']=26; n[-1]['children'][0]['y']=14
    n += [frame('Acción · aviso',556,576,290,52,p['surface'],14,p['line'],[icon('Escanear','scan',22,14,p['accent'],24),text('Texto aviso','Desde aviso bancario',60,16,212,24,15,p['ink'],'Medium')])]
    n += [frame('Detalle cerrado',272,664,976,68,p['surface'],16,p['line'],[icon('Gráfico','chart',22,22,p['muted'],24),text('Título detalle','Detalle y evolución',64,16,760,25,15,p['ink'],'Medium'),text('Subtítulo detalle','Cuentas · evolución mensual · categorías',64,42,760,18,11,p['muted']),icon('Abrir detalle','right',932,22,p['muted'],24)])]
    return frame('Dashboard · Mac · '+theme,0,0,1280,800,p['bg'],children=n)


def svg_node(n):
    x,y=n['x'],n['y']; w,h=n['width'],n['height']; name=html.escape(n['name'],quote=True)
    if n['type']=='frame':
        stroke=f' stroke="{n["stroke"]}" stroke-width="1"' if n.get('stroke') else ''
        return f'<g id="{name}" transform="translate({x} {y})"><rect width="{w}" height="{h}" rx="{n.get("radius",0)}" fill="{n["fill"]}"{stroke}/>'+''.join(svg_node(c) for c in n['children'])+'</g>'
    if n['type']=='icon':
        inner=n['svg'].split('>',1)[1].rsplit('</svg>',1)[0]
        return f'<g aria-label="{name}" transform="translate({x} {y}) scale({w/24})">{inner}</g>'
    anchor={'LEFT':'start','CENTER':'middle','RIGHT':'end'}[n['align']]
    tx=x if anchor=='start' else x+w/2 if anchor=='middle' else x+w
    weight={'Regular':400,'Medium':500,'Semi Bold':600,'Bold':700}[n['weight']]
    return f'<text aria-label="{name}" x="{tx}" y="{y+n["size"]*0.94}" fill="{n["color"]}" font-size="{n["size"]}" font-weight="{weight}" text-anchor="{anchor}" font-family="Inter, -apple-system, BlinkMacSystemFont, Arial, sans-serif">{html.escape(n["text"])}</text>'


def generate():
    frames=[]
    for theme,palette in [('Claro',LIGHT),('Oscuro',DARK)]:
        for device,build in [('iPhone',mobile),('Mac',desktop)]:
            design=build(palette,theme)
            frames.append(design)
            svg=f'<svg xmlns="http://www.w3.org/2000/svg" width="{design["width"]}" height="{design["height"]}" viewBox="0 0 {design["width"]} {design["height"]}" role="img" aria-label="Dashboard de Hogar Finanzas, datos de ejemplo">'+svg_node(design)+'</svg>'
            (ROOT/f'Dashboard-{device}-{theme.lower()}.svg').write_text(svg)
    spec=dict(name='Hogar Finanzas · Dashboard',version=1,notice='Datos ficticios de diseño. No representa una sincronización ni validación nativa.',frames=frames)
    (ROOT/'dashboard-editable.json').write_text(json.dumps(spec,ensure_ascii=False,indent=2))
    plugin='''// Importador local: no solicita red ni credenciales. Todos los textos se crean con createText().
const DESIGN = __SPEC__;
const rgb = hex => ({r:parseInt(hex.slice(1,3),16)/255,g:parseInt(hex.slice(3,5),16)/255,b:parseInt(hex.slice(5,7),16)/255});
const paint = hex => [{type:'SOLID',color:rgb(hex)}];
async function main() {
 const fonts = await figma.listAvailableFontsAsync();
 const family = fonts.some(f => f.fontName.family === 'Inter') ? 'Inter' : 'Roboto';
 const names = new Map();
 for (const weight of ['Regular','Medium','Semi Bold','Bold']) {
  const match = fonts.find(f => f.fontName.family===family && f.fontName.style.replace(/\\s/g,'').toLowerCase()===weight.replace(/\\s/g,'').toLowerCase());
  const selected = match ? match.fontName : {family,style:'Regular'};
  await figma.loadFontAsync(selected); names.set(weight,selected);
 }
 const created=[];
 function build(def,parent) {
  let node;
  if(def.type==='text') {
   node=figma.createText(); parent.appendChild(node);
   node.fontName=names.get(def.weight); node.fontSize=def.size;
   node.lineHeight={unit:'PERCENT',value:120}; node.characters=def.text;
   node.textAlignHorizontal=def.align; node.textAutoResize='NONE';
   node.fills=paint(def.color); node.resize(def.width,def.height);
  } else if(def.type==='icon') {
   node=figma.createNodeFromSvg(def.svg); parent.appendChild(node); node.resize(def.width,def.height);
  } else {
   node=figma.createFrame(); parent.appendChild(node); node.resize(def.width,def.height);
   if(parent===figma.currentPage) created.push(node);
   node.fills=paint(def.fill); node.cornerRadius=def.radius || 0; node.clipsContent=false;
   if(def.stroke){node.strokes=paint(def.stroke);node.strokeWeight=1;node.strokeAlign='INSIDE';}
   else node.strokes=[];
   for(const child of def.children || []) build(child,node);
  }
  node.name=def.name; node.x=def.x; node.y=def.y; return node;
 }
 try {
  DESIGN.frames.forEach((frame,index) => {
   const node=build(frame,figma.currentPage); node.x=(index%2)*450; node.y=Math.floor(index/2)*940;
   // Espacio amplio entre los formatos iPhone (390) y Mac (1280).
  });
  figma.currentPage.selection=created; figma.viewport.scrollAndZoomIntoView(created);
  figma.closePlugin('Cuatro dashboards creados: iPhone/Mac, claro/oscuro. Textos y capas editables.');
 } catch(error) {
  for(const node of created) node.remove();
  throw error;
 }
}
main().catch(() => figma.closePlugin('No se pudo importar. Comprueba que Inter o Roboto estén disponibles y ejecuta el plugin en Figma Design.'));
'''.replace('__SPEC__',json.dumps(spec,ensure_ascii=False,separators=(',',':')))
    (ROOT/'Figma'/'code.js').write_text(plugin)
    manifest=dict(id='hogar-finanzas-dashboard-editable',name='Hogar Finanzas · Dashboard editable',api='1.0.0',main='code.js',editorType=['figma'],documentAccess='dynamic-page',networkAccess={'allowedDomains':['none']})
    (ROOT/'Figma'/'manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2))

if __name__=='__main__':generate()
