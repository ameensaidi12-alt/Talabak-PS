import 'dart:async';

class PollingService {
  Timer? _timer;
  final Function _onPoll;
  final Duration interval;

  PollingService({
    required Function onPoll,
    this.interval = const Duration(seconds: 30),
  }) : _onPoll = onPoll;

  void start() {
    _timer?.cancel();
    _timer = Timer.periodic(interval, (timer) {
      _onPoll();
    });
    // Immediate poll
    _onPoll();
  }

  void stop() {
    _timer?.cancel();
  }
}
