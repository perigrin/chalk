our $v = 1; for my $n (qw(v)) { no strict 'refs'; *{"main::$n"} = \5; } print "$v\n";
