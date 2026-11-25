my ($lo,$hi)=(0,10); while ($lo<$hi) { my $mid=int(($lo+$hi)/2); if ($mid*$mid<30) { $lo=$mid+1 } else { $hi=$mid } } print "$lo\n";
