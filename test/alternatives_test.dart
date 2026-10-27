import 'package:flutter_test/flutter_test.dart';
import 'package:vietread/utils/alternatives.dart';

/// Test parser Dart — khớp **1-1** với `backend/app/alternatives.py`:
///
/// - marker chuẩn `{nghĩa1|nghĩa2}` chỉ chứa nghĩa tiếng Việt;
/// - dữ liệu cũ `{中文|nghĩa1|…}` parse được, tách khóa chữ Hán ra
///   ([Marker.key]) nhưng KHÔNG BAO GIỜ nằm trong [Marker.meanings];
/// - mọi phần tử chứa ký tự CJK (chữ Hán + dấu câu CJK) bị loại;
/// - sau khi loại còn < 2 nghĩa → không còn là marker;
/// - [buildMarker] không bao giờ sinh marker chứa chữ Hán.
void main() {
  test('marker chuẩn chỉ chứa nghĩa Việt', () {
    const String source = 'Còn {vì|là} rút đi.';
    final List<Marker> markers = parseMarkers(source);
    expect(markers, hasLength(1));
    expect(markers.single.meanings, <String>['vì', 'là']);
    expect(markers.single.key, isNull);
    expect(hasCjk(markers.single.rawOf(source)), isFalse);
    expect(countMarkers(source), 1);
  });

  test('dữ liệu cũ {为|vì|là|vi}: tách khóa cũ, nghĩa toàn Việt', () {
    final List<Marker> markers = parseMarkers(
      'còn {为|vì|là|vi} rút đi kiều mị',
    );
    expect(markers, hasLength(1));
    expect(markers.single.key, '为'); // khóa cũ — chỉ nội bộ, không hiển thị
    expect(markers.single.meanings, <String>['vì', 'là', 'vi']);
    // Nghĩa KHÔNG BAO GIỜ chứa chữ Hán dù raw dữ liệu cũ còn khóa
    expect(markers.single.meanings.any(hasCjk), isFalse);
    expect(resolveMarkers('còn {为|vì|là|vi} rút'), 'còn vì rút');
  });

  test('resolve bỏ chữ Hán và dấu {} — dữ liệu cũ lẫn mới', () {
    expect(resolveMarkers('còn {为|vì|là|vi} rút'), 'còn vì rút');
    expect(resolveMarkers('a {vì|là} b'), 'a vì b');
    expect(resolveMarkers('x {为|vì} y'), 'x vì y'); // <2 nghĩa → bỏ {}
    expect(resolveMarkers('x {为} y'), 'x  y'); // không còn nghĩa Việt → bỏ hẳn
    expect(resolveMarkers('chương 1'), 'chương 1');
    expect(resolveMarkers(''), '');
  });

  test('parse/count bỏ chỗ không còn là marker sau khi loại CJK', () {
    expect(countMarkers('a {为|vì} b'), 0); // còn 1 nghĩa → không marker
    expect(countMarkers('thẻ {card siêu nhân}'), 0); // 1 nghĩa → không marker
    expect(parseMarkers('a {为} b'), isEmpty); // mỗi khóa Hán → bỏ
    expect(countMarkers('x {a|b} y {c:d} z'), 2); // dạng cũ a:b vẫn marker
  });

  test('markerAt mở đúng chỗ', () {
    const String text = 'Còn {vì|là} rút.';
    final Marker? hit = markerAt(text, text.indexOf('{') + 1);
    expect(hit, isNotNull);
    expect(hit!.meanings, <String>['vì', 'là']);
    expect(markerAt(text, 0), isNull);
  });

  test('buildMarker không bao giờ chứa chữ Hán', () {
    expect(buildMarker(<String>['vì', 'là']), '{vì|là}');
    expect(
      buildMarker(<String>['为', 'vì', 'là']),
      '{vì|là}',
    ); // loại phần tử Hán
    expect(buildMarker(<String>['为', '之']), ''); // toàn Hán → không marker
    expect(buildMarker(<String>['chỉ một']), ''); // <2 nghĩa → không marker
    expect(hasCjk(buildMarker(<String>['vì', 'là'])), isFalse);
    // Trần 6 nghĩa như backend
    expect(
      buildMarker(List<String>.generate(9, (int i) => 'n$i')),
      '{n0|n1|n2|n3|n4|n5}',
    );
  });

  test('dấu câu CJK cũng bị loại khỏi nghĩa', () {
    expect(buildMarker(<String>['vì、là', 'vi', 'khác']), '{vi|khác}');
    expect(buildMarker(<String>['vì、là', 'vi']), '');
  });
}
