our $cnt = 0; for my $n (qw(a b)) { no strict 'refs'; *{"mk_$n"} = sub { $cnt++; $n } } print mk_a(), mk_b(), $cnt, "\n";
