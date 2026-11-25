use v5.38; use feature "class"; no warnings; class P { field @l = (1,2); method snap { my @c=@l; push @l,3; scalar(@c) . scalar(@l) } } print P->new->snap, "\n";
