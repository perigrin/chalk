use v5.38; use feature "class"; no warnings; class P { field %h = (a=>1); method snap { my %c=%h; $h{b}=2; scalar(keys %c) . scalar(keys %h) } } print P->new->snap, "\n";
