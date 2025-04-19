extension KotlinScopeFunctions<T> on T {
  R let<R>(R Function(T it) block) => block(this);

  T also(void Function(T it) block) {
    block(this);
    return this;
  }

  R run<R>(R Function() block) => block();

  T apply(void Function(T it) block) {
    block(this);
    return this;
  }
}
