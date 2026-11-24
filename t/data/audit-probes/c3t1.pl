my $t0 = time; sleep 1; my $t1 = time;
print $t1 > $t0 ? "ok\n" : "same second\n";
