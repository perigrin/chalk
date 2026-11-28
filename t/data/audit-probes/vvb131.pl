my $s = ""; my $i = 0; while ($i++ < 3) { my %h; $s .= scalar(keys %h); $h{$i} = 1; my $r = \%h } print "$s\n";
