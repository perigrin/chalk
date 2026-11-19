our $g = 1; sub setg { $g = $_[0] } my $x = $g + 1; setg(10); my $y = $g + 1; print "$x $y\n";
