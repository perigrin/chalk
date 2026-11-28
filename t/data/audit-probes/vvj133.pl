my %h = (a=>1,b=>2); my @s = @h{qw(a b)}; my ($x, $y) = @h{qw(b a)}; my %sub; @sub{qw(a)} = @h{qw(a)}; print "@s$x$y", join(",", %sub), "\n";
