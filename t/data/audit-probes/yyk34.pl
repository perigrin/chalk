use feature 'class'; no warnings; class P { field $n = 0; method inc { ++$n } } my $p = P->new; my $q = P->new; $p->inc; $p->inc; $q->inc; print $p->inc, $q->inc, "\n";
