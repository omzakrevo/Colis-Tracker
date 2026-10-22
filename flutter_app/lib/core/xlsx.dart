import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

/// Écrit un classeur Excel (.xlsx) sans dépendance lourde : plusieurs feuilles, ligne d'en-tête en gras,
/// nombres et dates reconnus par Excel. Une cellule peut être un `String`, un nombre, un `DateTime` ou `null`.
class FeuilleXlsx {
  FeuilleXlsx(this.nom, this.entetes, this.lignes, {this.largeurs});
  final String nom;
  final List<String> entetes;
  final List<List<Object?>> lignes;

  /// Largeurs de colonnes (en caractères) ; par défaut ajustées au contenu.
  final List<double>? largeurs;
}

String _echapper(String s) => s
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    // caractères interdits en XML 1.0
    .replaceAll(RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F]'), '');

/// Nom de colonne Excel : 0 → A, 25 → Z, 26 → AA.
String _col(int i) {
  var n = i + 1;
  var s = '';
  while (n > 0) {
    final r = (n - 1) % 26;
    s = String.fromCharCode(65 + r) + s;
    n = (n - 1) ~/ 26;
  }
  return s;
}

/// Numéro de série Excel d'une date (jours depuis le 30/12/1899).
double _serie(DateTime d) => DateTime.utc(d.year, d.month, d.day, d.hour, d.minute, d.second)
        .difference(DateTime.utc(1899, 12, 30))
        .inSeconds /
    86400;

String _nomFeuille(String s, Set<String> pris) {
  var n = s.replaceAll(RegExp(r'[\\/?*\[\]:]'), ' ').trim();
  if (n.isEmpty) n = 'Feuille';
  if (n.length > 31) n = n.substring(0, 31);
  var base = n;
  var i = 2;
  while (pris.contains(n.toLowerCase())) {
    final suf = ' ($i)';
    n = (base.length + suf.length > 31 ? base.substring(0, 31 - suf.length) : base) + suf;
    i++;
  }
  pris.add(n.toLowerCase());
  return n;
}

String _feuilleXml(FeuilleXlsx f) {
  final b = StringBuffer(
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
    '<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">',
  );
  final n = f.entetes.length;
  b.write('<sheetViews><sheetView workbookViewId="0"><pane ySplit="1" topLeftCell="A2" activePane="bottomLeft" state="frozen"/></sheetView></sheetViews>');
  b.write('<cols>');
  for (var c = 0; c < n; c++) {
    var w = f.largeurs != null && c < f.largeurs!.length ? f.largeurs![c] : f.entetes[c].length + 4.0;
    if (f.largeurs == null) {
      for (final l in f.lignes.take(300)) {
        if (c < l.length && l[c] is String) {
          final len = (l[c] as String).length + 2.0;
          if (len > w) w = len;
        }
      }
      if (w > 48) w = 48;
    }
    b.write('<col min="${c + 1}" max="${c + 1}" width="${w.toStringAsFixed(1)}" customWidth="1"/>');
  }
  b.write('</cols><sheetData>');
  b.write('<row r="1">');
  for (var c = 0; c < n; c++) {
    b.write('<c r="${_col(c)}1" s="1" t="inlineStr"><is><t>${_echapper(f.entetes[c])}</t></is></c>');
  }
  b.write('</row>');
  for (var r = 0; r < f.lignes.length; r++) {
    final row = r + 2;
    b.write('<row r="$row">');
    final l = f.lignes[r];
    for (var c = 0; c < l.length && c < n; c++) {
      final v = l[c];
      final ref = '${_col(c)}$row';
      if (v == null) continue;
      if (v is DateTime) {
        final hasTime = v.hour != 0 || v.minute != 0;
        b.write('<c r="$ref" s="${hasTime ? 3 : 2}"><v>${_serie(v)}</v></c>');
      } else if (v is num) {
        b.write('<c r="$ref" s="${v is int ? 0 : 4}"><v>$v</v></c>');
      } else {
        b.write('<c r="$ref" t="inlineStr"><is><t xml:space="preserve">${_echapper('$v')}</t></is></c>');
      }
    }
    b.write('</row>');
  }
  b.write('</sheetData>');
  if (n > 0) b.write('<autoFilter ref="A1:${_col(n - 1)}${f.lignes.length + 1}"/>');
  b.write('</worksheet>');
  return b.toString();
}

/// Construit le fichier .xlsx.
Uint8List classeurXlsx(List<FeuilleXlsx> feuilles) {
  assert(feuilles.isNotEmpty);
  final pris = <String>{};
  final noms = [for (final f in feuilles) _nomFeuille(f.nom, pris)];
  final a = Archive();
  void ajouter(String chemin, String contenu) => a.addFile(ArchiveFile.bytes(chemin, utf8.encode(contenu)));

  ajouter(
    '[Content_Types].xml',
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
    '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
    '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
    '<Default Extension="xml" ContentType="application/xml"/>'
    '<Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>'
    '<Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>'
    '${[for (var i = 0; i < feuilles.length; i++) '<Override PartName="/xl/worksheets/sheet${i + 1}.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>'].join()}'
    '</Types>',
  );
  ajouter(
    '_rels/.rels',
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
    '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
    '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>'
    '</Relationships>',
  );
  ajouter(
    'xl/workbook.xml',
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
    '<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" '
    'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheets>'
    '${[for (var i = 0; i < feuilles.length; i++) '<sheet name="${_echapper(noms[i])}" sheetId="${i + 1}" r:id="rId${i + 1}"/>'].join()}'
    '</sheets></workbook>',
  );
  ajouter(
    'xl/_rels/workbook.xml.rels',
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
    '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
    '${[for (var i = 0; i < feuilles.length; i++) '<Relationship Id="rId${i + 1}" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet${i + 1}.xml"/>'].join()}'
    '<Relationship Id="rId${feuilles.length + 1}" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>'
    '</Relationships>',
  );
  // Styles : 0 normal, 1 en-tête gras sur fond gris, 2 date, 3 date + heure, 4 montant avec séparateur de milliers.
  ajouter(
    'xl/styles.xml',
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
    '<styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">'
    '<numFmts count="2"><numFmt numFmtId="164" formatCode="dd/mm/yyyy"/><numFmt numFmtId="165" formatCode="dd/mm/yyyy hh:mm"/></numFmts>'
    '<fonts count="2"><font><sz val="11"/><name val="Calibri"/></font><font><b/><sz val="11"/><name val="Calibri"/></font></fonts>'
    '<fills count="3"><fill><patternFill patternType="none"/></fill><fill><patternFill patternType="gray125"/></fill>'
    '<fill><patternFill patternType="solid"><fgColor rgb="FFE5E7EB"/><bgColor indexed="64"/></patternFill></fill></fills>'
    '<borders count="1"><border><left/><right/><top/><bottom/><diagonal/></border></borders>'
    '<cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>'
    '<cellXfs count="5">'
    '<xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/>'
    '<xf numFmtId="0" fontId="1" fillId="2" borderId="0" xfId="0" applyFont="1" applyFill="1"/>'
    '<xf numFmtId="164" fontId="0" fillId="0" borderId="0" xfId="0" applyNumberFormat="1"/>'
    '<xf numFmtId="165" fontId="0" fillId="0" borderId="0" xfId="0" applyNumberFormat="1"/>'
    '<xf numFmtId="3" fontId="0" fillId="0" borderId="0" xfId="0" applyNumberFormat="1"/>'
    '</cellXfs></styleSheet>',
  );
  for (var i = 0; i < feuilles.length; i++) {
    ajouter('xl/worksheets/sheet${i + 1}.xml', _feuilleXml(feuilles[i]));
  }
  return Uint8List.fromList(ZipEncoder().encode(a));
}
