use v5.38; use feature "class"; no warnings; class P { field @l = (1,2); method l { @l } method add { push @l,3 } } my $o=P->new; my @c=$o->l; $o->add; print scalar(@c), scalar($o->l), "\n";
