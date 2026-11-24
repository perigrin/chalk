my $c=0; my @s=map { my $n=$_; sub { $c+=$n } } 1..3; $_->() for @s, @s; print "$c\n";
