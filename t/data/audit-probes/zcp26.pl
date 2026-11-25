my @a=(1,2); for (1..2) { my @c=@a; push @a,$_; print scalar(@c) } print "\n";
