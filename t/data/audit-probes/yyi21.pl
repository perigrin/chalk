sub inc { $_[0]++ } my @a=(1,2); my @t = map { inc($_) } @a; print "@a @t\n";
