import '../core/json_reading.dart';
import '../core/open_enum.dart';

/// Who may play a playback id.
final class PlaybackPolicy extends MuxOpenEnum {
  const PlaybackPolicy._(super.value);

  /// Wraps a value this package does not know.
  const PlaybackPolicy.unknown(super.value);

  /// Playable by anyone who has the playback id.
  static const public = PlaybackPolicy._('public');

  /// Playable only with a signed token.
  static const signed = PlaybackPolicy._('signed');

  /// Protected with DRM.
  static const drm = PlaybackPolicy._('drm');

  /// The values known when this package was generated.
  static const values = [public, signed, drm];

  /// Decodes a wire value, preserving one this package does not know.
  factory PlaybackPolicy.fromWire(String value) => values.firstWhere(
        (known) => known.value == value,
        orElse: () => PlaybackPolicy.unknown(value),
      );

  @override
  bool get isKnown => values.contains(this);
}

/// The encoding quality tier of an asset.
final class VideoQuality extends MuxOpenEnum {
  const VideoQuality._(super.value);

  /// Wraps a value this package does not know.
  const VideoQuality.unknown(super.value);

  /// The lowest tier.
  static const basic = VideoQuality._('basic');

  /// The default tier.
  static const plus = VideoQuality._('plus');

  /// The highest tier.
  static const premium = VideoQuality._('premium');

  /// The values known when this package was generated.
  static const values = [basic, plus, premium];

  /// Decodes a wire value, preserving one this package does not know.
  factory VideoQuality.fromWire(String value) => values.firstWhere(
        (known) => known.value == value,
        orElse: () => VideoQuality.unknown(value),
      );

  @override
  bool get isKnown => values.contains(this);
}

/// Whether a downloadable master of the asset is available.
final class MasterAccess extends MuxOpenEnum {
  const MasterAccess._(super.value);

  /// Wraps a value this package does not know.
  const MasterAccess.unknown(super.value);

  /// A temporary master download URL is (or is being made) available.
  static const temporary = MasterAccess._('temporary');

  /// No master download.
  static const none = MasterAccess._('none');

  /// The values known when this package was generated.
  static const values = [temporary, none];

  /// Decodes a wire value, preserving one this package does not know.
  factory MasterAccess.fromWire(String value) => values.firstWhere(
        (known) => known.value == value,
        orElse: () => MasterAccess.unknown(value),
      );

  @override
  bool get isKnown => values.contains(this);
}

/// Settings for the asset Mux creates from an upload or a live stream.
///
/// Covers the settings this package's callers use today; [extra] carries any
/// other `new_asset_settings` field verbatim until the generated model lands.
final class AssetOptions {
  /// Creates asset settings.
  const AssetOptions({
    this.playbackPolicies,
    this.videoQuality,
    this.masterAccess,
    this.normalizeAudio,
    this.passthrough,
    this.test,
    this.extra = const {},
  });

  /// Decodes the `new_asset_settings` object of an upload.
  factory AssetOptions.fromJson(Map<String, Object?> json) => AssetOptions(
        playbackPolicies: json
            .optStringList('playback_policies')
            .map(PlaybackPolicy.fromWire)
            .toList(growable: false),
        videoQuality: json.optEnum('video_quality', VideoQuality.fromWire),
        masterAccess: json.optEnum('master_access', MasterAccess.fromWire),
        normalizeAudio: json.optBool('normalize_audio'),
        passthrough: json.optString('passthrough'),
        test: json.optBool('test'),
        extra: {
          for (final entry in json.entries)
            if (!_knownKeys.contains(entry.key)) entry.key: entry.value,
        },
      );

  static const Set<String> _knownKeys = {
    'playback_policies',
    'video_quality',
    'master_access',
    'normalize_audio',
    'passthrough',
    'test',
  };

  /// The playback policies of the playback ids to create.
  final List<PlaybackPolicy>? playbackPolicies;

  /// The encoding quality tier.
  final VideoQuality? videoQuality;

  /// Whether a master download should be made available.
  final MasterAccess? masterAccess;

  /// Whether to normalise the audio track loudness.
  final bool? normalizeAudio;

  /// Arbitrary metadata, up to 255 characters, echoed back on the asset.
  final String? passthrough;

  /// Whether the asset is a test asset (watermarked, deleted after 24 h).
  final bool? test;

  /// Any other setting, sent and received verbatim.
  final Map<String, Object?> extra;

  /// Encodes the settings for a request body, omitting absent fields.
  Map<String, Object?> toJson() => {
        if (playbackPolicies != null)
          'playback_policies': [
            for (final policy in playbackPolicies!) policy.value,
          ],
        if (videoQuality != null) 'video_quality': videoQuality!.value,
        if (masterAccess != null) 'master_access': masterAccess!.value,
        if (normalizeAudio != null) 'normalize_audio': normalizeAudio,
        if (passthrough != null) 'passthrough': passthrough,
        if (test != null) 'test': test,
        ...extra,
      };
}
