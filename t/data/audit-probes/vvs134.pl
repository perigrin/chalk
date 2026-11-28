sub f { return } my $r = [f(), 1, f()]; print scalar(@$r), "\n";
