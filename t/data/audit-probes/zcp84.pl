use v5.38; use feature "class"; no warnings; class P { field $n :param = 1; method n { $n } method inc { $n++ } } my $o=P->new; my $v=$o->n; $o->inc; print $v, $o->n, "\n";
