sub mk { return bless {}, $_[0] } my $o = mk("K"); my $ok = printf("%s\n", "made"); print "$ok\n";
