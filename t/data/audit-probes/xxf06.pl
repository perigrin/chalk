our $g = 1; my $i = 0; while ($i++ < 3) { local $g = $g * 2; next if $i == 2; print $g } print $g, "\n";
