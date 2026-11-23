my $cfg={a=>1}; sub upd { my $c=shift; $c->{a}=2; $c={a=>3}; } upd($cfg); print $cfg->{a},"\n";
