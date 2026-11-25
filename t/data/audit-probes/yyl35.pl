my $text = "one two three two one"; my %c; $c{$_}++ for $text =~ /\w+/g; my @top = sort { $c{$b} <=> $c{$a} || $a cmp $b } keys %c; print join(",", map { "$_$c{$_}" } @top), "\n";
