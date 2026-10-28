enum UpdateStep { downloading, updating, loading, done }

class UpdateStatus {
  final String feedId;
  final UpdateStep step;
  final int processed;
  final int total;

  const UpdateStatus(this.feedId, this.step, this.processed, this.total);
}

