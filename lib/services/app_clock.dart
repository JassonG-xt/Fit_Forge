abstract interface class AppClock {
  DateTime now();
}

class SystemAppClock implements AppClock {
  const SystemAppClock();

  @override
  DateTime now() => DateTime.now();
}

class FixedAppClock implements AppClock {
  const FixedAppClock(this.fixedNow);

  final DateTime fixedNow;

  @override
  DateTime now() => fixedNow;
}
