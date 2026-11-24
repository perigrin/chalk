my $t0 = time; my $s = sleep 1; my $t1 = time;
print $s, " ", ($t1 - $t0 >= 1 ? "moved" : "still"), "\n";
