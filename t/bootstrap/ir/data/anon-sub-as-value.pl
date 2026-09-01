sub apply { my $f = shift; return 7 }
$SIG{__WARN__} = sub { 1; };
my $r = apply(sub { 7 });
print $r;
