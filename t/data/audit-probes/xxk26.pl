my $s = "abc"; sub su { $_[0] =~ s/b/-/ } su($s); su($s) or print "no"; print "$s\n";
