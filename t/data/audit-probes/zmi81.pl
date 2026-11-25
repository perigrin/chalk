sub fib { my $n=shift; $n<2 ? $n : fib($n-1)+fib($n-2) } print fib(15), "\n";
