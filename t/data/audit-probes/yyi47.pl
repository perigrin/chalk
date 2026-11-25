sub fib { my $n = shift; $n < 2 ? $n : fib($n-1) + fib($n-2) } sub ack { my ($m,$n)=@_; $m==0 ? $n+1 : $n==0 ? ack($m-1,1) : ack($m-1, ack($m,$n-1)) } print fib(20), " ", ack(2,3), "\n";
