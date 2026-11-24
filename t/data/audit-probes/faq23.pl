sub first { $_[0]=~/(\w)/ ? $1 : "" } "zz"=~/(z)/; my $f=first("ab"); print "$f$1\n";
