class ExclusiveResult<T> {
  const ExclusiveResult.acquired(this.value) : acquired = true;
  const ExclusiveResult.timeout() : acquired = false, value = null;

  final bool acquired;
  final T? value;
}

abstract interface class ObservedArticlePersistence {
  Future<String?> read();

  Future<void> write(String value);

  Future<ExclusiveResult<T>> runExclusive<T>(Future<T> Function() action);
}
