use feature 'class'; no warnings; class P { field $v :param :reader; field $w :param(alt) = "d"; method w { $w } } my $o = P->new(v => 1, alt => 2); print $o->v, $o->w, P->new(v => 3)->w, "\n";
