our @g=(1); sub f { local @g=(2,3); my $z=shift; 1/$z } eval { f(0) }; print "@g\n";
