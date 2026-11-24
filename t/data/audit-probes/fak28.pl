my $x=1; my $f=sub { $x++ }; my @l=("$x", $f->(), "$x"); print "@l\n";
