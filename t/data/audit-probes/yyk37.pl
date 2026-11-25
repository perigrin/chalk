use feature 'class'; no warnings; class P { my $count = 0; field $id; ADJUST { $id = ++$count } method id { $id } sub total { $count } } P->new; P->new; print P->new->id, P::total(), "\n";
