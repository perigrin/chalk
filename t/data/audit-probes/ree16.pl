my @a=(1,2,3); sub tw { my $r=\@_; $r->[0]=7 } tw(@a); print "@a\n";
