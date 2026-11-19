sub outer { my $x = shift; my $in = sub { $x * 2 }; return $in->() + 1 } print outer(4), "\n";
