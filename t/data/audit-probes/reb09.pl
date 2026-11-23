my $r = eval { die { code => 7 } }; print $@->{code}, "\n";
