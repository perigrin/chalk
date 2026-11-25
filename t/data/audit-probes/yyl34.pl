my @l = qw(apple banana cherry); s/a/A/ for @l; my @c = map { s/e/E/r } @l; my @g = grep { /an/ } @l; my ($f) = grep { !/A/ } @l; print "@l|@c|@g|$f\n";
