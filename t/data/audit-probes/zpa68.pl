my @a=(1,2); sub inc { $_[0]++ } inc($_) for @a; print "@a\n";
