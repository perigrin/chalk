my $o = {}; my @r = (ref($o), ref(bless $o, "K"), ref($o)); print "@r\n";
