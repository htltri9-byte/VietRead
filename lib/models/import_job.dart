/// Model `ImportJob` — khớp `POST /imports` (`{ jobId }`) và
/// `GET /imports/{jobId}` (`{ status, progress, storyId?, error? }`).
///
/// Trạng thái: `Pending` | `Running` | `Done` | `Failed` (Phần B/C4).
class ImportJob {
  const ImportJob({
    required this.jobId,
    required this.status,
    this.progress = 0,
    this.storyId,
    this.error,
  });

  final int jobId;
  final String status;

  /// Tiến độ 0–100 (% chương đã dịch).
  final int progress;
  final int? storyId;
  final String? error;

  bool get isPending => status == 'Pending';
  bool get isRunning => status == 'Running';
  bool get isDone => status == 'Done';
  bool get isFailed => status == 'Failed';

  /// Nhãn tiếng Việt cho màn hình theo dõi (A3.10).
  String get statusLabel {
    switch (status) {
      case 'Pending':
        return 'Đang chờ';
      case 'Running':
        return 'Đang chạy';
      case 'Done':
        return 'Hoàn tất';
      case 'Failed':
        return 'Thất bại';
      default:
        return status;
    }
  }

  /// Tiến độ dạng 0.0–1.0 để vẽ thanh progress.
  double get progress01 => (progress.clamp(0, 100)) / 100.0;

  factory ImportJob.fromJson(Map<String, dynamic> json) => ImportJob(
    jobId: (json['jobId'] as num?)?.toInt() ?? 0,
    status: json['status'] as String? ?? 'Pending',
    progress: (json['progress'] as num?)?.toInt() ?? 0,
    storyId: (json['storyId'] as num?)?.toInt(),
    error: json['error'] as String?,
  );

  Map<String, dynamic> toJson() => <String, dynamic>{
    'jobId': jobId,
    'status': status,
    'progress': progress,
    'storyId': storyId,
    'error': error,
  };
}
