use v5.38; use experimental "class"; class P { field %h = (a=>1); method go { my %c = %h; $c{a}=2; return "$h{a} $c{a}" } } print P->new->go, "\n";
