import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:image/image.dart' as img;

/// Builds a minimal but valid .pptx file where each input image becomes one
/// full-slide picture (contained, letterboxed if the aspect ratio doesn't
/// match). This is a mechanical "one page per slide" conversion, not a real
/// PDF-to-editable-PowerPoint reconstruction — there is no free service that
/// turns a PDF page back into editable text boxes, so the pictures are
/// placed as-is, exactly like printing a page and pasting a photo of it into
/// a slide.
class PptxWriterService {
  // Standard 16:9 widescreen slide size, in EMUs (914400 EMU = 1 inch).
  static const int _slideWidth = 12192000;
  static const int _slideHeight = 6858000;

  static Uint8List buildPptx(List<Uint8List> jpegOrPngImages) {
    final archive = Archive();

    archive.add(_textFile('[Content_Types].xml', _contentTypesXml(jpegOrPngImages.length)));
    archive.add(_textFile('_rels/.rels', _rootRelsXml));
    archive.add(_textFile('docProps/core.xml', _coreXml));
    archive.add(_textFile('docProps/app.xml', _appXml(jpegOrPngImages.length)));
    archive.add(_textFile('ppt/presentation.xml', _presentationXml(jpegOrPngImages.length)));
    archive.add(_textFile('ppt/_rels/presentation.xml.rels', _presentationRelsXml(jpegOrPngImages.length)));
    archive.add(_textFile('ppt/theme/theme1.xml', _themeXml));
    archive.add(_textFile('ppt/slideMasters/slideMaster1.xml', _slideMasterXml));
    archive.add(_textFile('ppt/slideMasters/_rels/slideMaster1.xml.rels', _slideMasterRelsXml));
    archive.add(_textFile('ppt/slideLayouts/slideLayout1.xml', _slideLayoutXml));
    archive.add(_textFile('ppt/slideLayouts/_rels/slideLayout1.xml.rels', _slideLayoutRelsXml));

    for (var i = 0; i < jpegOrPngImages.length; i++) {
      final bytes = jpegOrPngImages[i];
      final decoded = img.decodeImage(bytes);
      final w = decoded?.width.toDouble() ?? 1;
      final h = decoded?.height.toDouble() ?? 1;
      final rect = _containRect(w, h);

      archive.add(_textFile('ppt/slides/slide${i + 1}.xml', _slideXml(rect)));
      archive.add(_textFile(
        'ppt/slides/_rels/slide${i + 1}.xml.rels',
        _slideRelsXml(i + 1),
      ));
      archive.add(ArchiveFile('ppt/media/image${i + 1}.png', bytes.length, bytes));
    }

    final zipped = ZipEncoder().encodeBytes(archive);
    return Uint8List.fromList(zipped);
  }

  static ArchiveFile _textFile(String name, String content) {
    final bytes = Uint8List.fromList(content.codeUnits);
    return ArchiveFile(name, bytes.length, bytes);
  }

  /// Position/size (in EMUs) for an image of [w]x[h] pixels centered and
  /// scaled to fit inside the slide without distorting its aspect ratio.
  static ({int x, int y, int cx, int cy}) _containRect(double w, double h) {
    final scale = (w / h > _slideWidth / _slideHeight)
        ? _slideWidth / w
        : _slideHeight / h;
    final cx = (w * scale).round();
    final cy = (h * scale).round();
    return (
      x: (_slideWidth - cx) ~/ 2,
      y: (_slideHeight - cy) ~/ 2,
      cx: cx,
      cy: cy,
    );
  }

  static String _contentTypesXml(int slideCount) {
    final overrides = StringBuffer();
    for (var i = 1; i <= slideCount; i++) {
      overrides.write(
        '<Override PartName="/ppt/slides/slide$i.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.slide+xml"/>',
      );
    }
    return '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
<Default Extension="xml" ContentType="application/xml"/>
<Default Extension="png" ContentType="image/png"/>
<Override PartName="/ppt/presentation.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.presentation.main+xml"/>
<Override PartName="/ppt/slideMasters/slideMaster1.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.slideMaster+xml"/>
<Override PartName="/ppt/slideLayouts/slideLayout1.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.slideLayout+xml"/>
<Override PartName="/ppt/theme/theme1.xml" ContentType="application/vnd.openxmlformats-officedocument.theme+xml"/>
$overrides
<Override PartName="/docProps/core.xml" ContentType="application/vnd.openxmlformats-package.core-properties+xml"/>
<Override PartName="/docProps/app.xml" ContentType="application/vnd.openxmlformats-officedocument.extended-properties+xml"/>
</Types>''';
  }

  static const _rootRelsXml = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="ppt/presentation.xml"/>
<Relationship Id="rId2" Type="http://schemas.openxmlformats.org/package/2006/relationships/metadata/core-properties" Target="docProps/core.xml"/>
<Relationship Id="rId3" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/extended-properties" Target="docProps/app.xml"/>
</Relationships>''';

  static const _coreXml = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<cp:coreProperties xmlns:cp="http://schemas.openxmlformats.org/package/2006/metadata/core-properties" xmlns:dc="http://purl.org/dc/elements/1.1/">
<dc:title>DocScanner Export</dc:title>
<dc:creator>DocScanner</dc:creator>
</cp:coreProperties>''';

  static String _appXml(int slideCount) => '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Properties xmlns="http://schemas.openxmlformats.org/officeDocument/2006/extended-properties">
<Application>DocScanner</Application>
<Slides>$slideCount</Slides>
</Properties>''';

  static String _presentationXml(int slideCount) {
    final ids = StringBuffer();
    for (var i = 0; i < slideCount; i++) {
      ids.write('<p:sldId id="${256 + i}" r:id="rId${2 + i}"/>');
    }
    return '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<p:presentation xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main">
<p:sldMasterIdLst><p:sldMasterId id="2147483648" r:id="rId1"/></p:sldMasterIdLst>
<p:sldIdLst>$ids</p:sldIdLst>
<p:sldSz cx="$_slideWidth" cy="$_slideHeight"/>
<p:notesSz cx="$_slideHeight" cy="$_slideWidth"/>
</p:presentation>''';
  }

  static String _presentationRelsXml(int slideCount) {
    final rels = StringBuffer();
    for (var i = 0; i < slideCount; i++) {
      rels.write(
        '<Relationship Id="rId${2 + i}" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/slide" Target="slides/slide${i + 1}.xml"/>',
      );
    }
    return '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/slideMaster" Target="slideMasters/slideMaster1.xml"/>
$rels
</Relationships>''';
  }

  static const _slideMasterXml = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<p:sldMaster xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main">
<p:cSld><p:spTree><p:nvGrpSpPr><p:cNvPr id="1" name=""/><p:cNvGrpSpPr/><p:nvPr/></p:nvGrpSpPr><p:grpSpPr/></p:spTree></p:cSld>
<p:clrMap bg1="lt1" tx1="dk1" bg2="lt2" tx2="dk2" accent1="accent1" accent2="accent2" accent3="accent3" accent4="accent4" accent5="accent5" accent6="accent6" hlink="hlink" folHlink="folHlink"/>
<p:sldLayoutIdLst><p:sldLayoutId id="2147483649" r:id="rId1"/></p:sldLayoutIdLst>
</p:sldMaster>''';

  static const _slideMasterRelsXml = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/slideLayout" Target="../slideLayouts/slideLayout1.xml"/>
<Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/theme" Target="../theme/theme1.xml"/>
</Relationships>''';

  static const _slideLayoutXml = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<p:sldLayout xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main" type="blank" preserve="1">
<p:cSld name="Blank"><p:spTree><p:nvGrpSpPr><p:cNvPr id="1" name=""/><p:cNvGrpSpPr/><p:nvPr/></p:nvGrpSpPr><p:grpSpPr/></p:spTree></p:cSld>
</p:sldLayout>''';

  static const _slideLayoutRelsXml = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/slideMaster" Target="../slideMasters/slideMaster1.xml"/>
</Relationships>''';

  static String _slideXml(({int x, int y, int cx, int cy}) rect) => '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<p:sld xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main">
<p:cSld><p:spTree>
<p:nvGrpSpPr><p:cNvPr id="1" name=""/><p:cNvGrpSpPr/><p:nvPr/></p:nvGrpSpPr>
<p:grpSpPr/>
<p:pic>
<p:nvPicPr><p:cNvPr id="2" name="Page"/><p:cNvPicPr><a:picLocks noChangeAspect="1"/></p:cNvPicPr><p:nvPr/></p:nvPicPr>
<p:blipFill><a:blip r:embed="rId1"/><a:stretch><a:fillRect/></a:stretch></p:blipFill>
<p:spPr>
<a:xfrm><a:off x="${rect.x}" y="${rect.y}"/><a:ext cx="${rect.cx}" cy="${rect.cy}"/></a:xfrm>
<a:prstGeom prst="rect"><a:avLst/></a:prstGeom>
</p:spPr>
</p:pic>
</p:spTree></p:cSld>
</p:sld>''';

  static String _slideRelsXml(int index) => '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/image" Target="../media/image$index.png"/>
</Relationships>''';

  // Minimal Office theme (color/font/format schemes trimmed to the parts
  // PowerPoint requires to open the file without repair prompts).
  static const _themeXml = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<a:theme xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" name="DocScanner">
<a:themeElements>
<a:clrScheme name="DocScanner">
<a:dk1><a:sysClr val="windowText" lastClr="000000"/></a:dk1>
<a:lt1><a:sysClr val="window" lastClr="FFFFFF"/></a:lt1>
<a:dk2><a:srgbClr val="1F1F1F"/></a:dk2>
<a:lt2><a:srgbClr val="EAEAEA"/></a:lt2>
<a:accent1><a:srgbClr val="2C5F6F"/></a:accent1>
<a:accent2><a:srgbClr val="4C8399"/></a:accent2>
<a:accent3><a:srgbClr val="7BA7B5"/></a:accent3>
<a:accent4><a:srgbClr val="A9CBD3"/></a:accent4>
<a:accent5><a:srgbClr val="D6E7EA"/></a:accent5>
<a:accent6><a:srgbClr val="0E2A32"/></a:accent6>
<a:hlink><a:srgbClr val="2C5F6F"/></a:hlink>
<a:folHlink><a:srgbClr val="7BA7B5"/></a:folHlink>
</a:clrScheme>
<a:fontScheme name="DocScanner">
<a:majorFont><a:latin typeface="Calibri"/><a:ea typeface=""/><a:cs typeface=""/></a:majorFont>
<a:minorFont><a:latin typeface="Calibri"/><a:ea typeface=""/><a:cs typeface=""/></a:minorFont>
</a:fontScheme>
<a:fmtScheme name="DocScanner">
<a:fillStyleLst>
<a:solidFill><a:schemeClr val="phClr"/></a:solidFill>
<a:solidFill><a:schemeClr val="phClr"/></a:solidFill>
<a:solidFill><a:schemeClr val="phClr"/></a:solidFill>
</a:fillStyleLst>
<a:lnStyleLst>
<a:ln w="6350"><a:solidFill><a:schemeClr val="phClr"/></a:solidFill></a:ln>
<a:ln w="12700"><a:solidFill><a:schemeClr val="phClr"/></a:solidFill></a:ln>
<a:ln w="19050"><a:solidFill><a:schemeClr val="phClr"/></a:solidFill></a:ln>
</a:lnStyleLst>
<a:effectStyleLst>
<a:effectStyle><a:effectLst/></a:effectStyle>
<a:effectStyle><a:effectLst/></a:effectStyle>
<a:effectStyle><a:effectLst/></a:effectStyle>
</a:effectStyleLst>
<a:bgFillStyleLst>
<a:solidFill><a:schemeClr val="phClr"/></a:solidFill>
<a:solidFill><a:schemeClr val="phClr"/></a:solidFill>
<a:solidFill><a:schemeClr val="phClr"/></a:solidFill>
</a:bgFillStyleLst>
</a:fmtScheme>
</a:themeElements>
</a:theme>''';
}
