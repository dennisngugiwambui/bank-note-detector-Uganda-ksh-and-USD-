import 'package:flutter/widgets.dart';

/// The few Phosphor icons the navigation uses (MIT, assets/fonts/Phosphor-LICENSE.txt).
/// Fonts are bundled directly: the phosphor_flutter package extends IconData,
/// which current Flutter no longer allows. Same codepoint in every weight.
abstract final class NavIcons {
  static const _home = 0xe2c6, _bell = 0xe0d0, _scan = 0xebb6, _wallet = 0xe68a, _gear = 0xe272;

  static const home = IconData(_home, fontFamily: 'PhosphorRegular');
  static const homeFill = IconData(_home, fontFamily: 'PhosphorFill');
  static const bell = IconData(_bell, fontFamily: 'PhosphorRegular');
  static const bellFill = IconData(_bell, fontFamily: 'PhosphorFill');
  static const scan = IconData(_scan, fontFamily: 'PhosphorRegular');
  static const scanBold = IconData(_scan, fontFamily: 'PhosphorBold');
  static const wallet = IconData(_wallet, fontFamily: 'PhosphorRegular');
  static const walletFill = IconData(_wallet, fontFamily: 'PhosphorFill');
  static const gear = IconData(_gear, fontFamily: 'PhosphorRegular');
  static const gearFill = IconData(_gear, fontFamily: 'PhosphorFill');
}
