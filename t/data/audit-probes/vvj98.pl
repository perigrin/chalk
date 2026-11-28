my @a = ("b", "a"); my @b = sort @a; my @c = sort { $b cmp $a } @a; my $f = (sort @a)[0]; print "@b@c$f\n";
