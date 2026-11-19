sub f { $_[0] =~ s/a/b/ } my $s = "aa"; f($s); my %h = (k => "aa"); f($h{k}); print "$s $h{k}\n";
