my @a=(1,2); my %h=(x=>1); my %c=(%h, n=>scalar(@a)); $h{x}=3; push @a, 3; print "$c{x}$c{n}\n";
