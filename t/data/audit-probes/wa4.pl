my @a = (1,2); my @b = (7,8,9); my $c = @ARGV; if ($c) { @a = @b } else { @a = (5) } print "@a\n";
