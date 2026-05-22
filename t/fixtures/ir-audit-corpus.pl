=== A1: bare VarDecl
class C { method m() { my $x = 1; return $x; } }
=== A2: VarDecl array literal
class C { method m() { my @list = (1, 2, 3); return scalar @list; } }
=== A3: VarDecl hash literal
class C { method m() { my %h = (a => 1, b => 2); return $h{a}; } }
=== A4: VarDecl no initializer
class C { method m() { my $x; $x = 1; return $x; } }
=== A5: VarDecl field
class C { field $x :param; method m() { return $x; } }
=== B1: bare push (list builtin, no captured value)
class C { method m() { my @list = (); push @list, 1; return scalar @list; } }
=== B2: bare print
class C { method m() { print "hi"; return 1; } }
=== B3: bare say
class C { method m() { say "hi"; return 1; } }
=== B4: bare die
class C { method m() { die "boom"; } }
=== B5: bare function call no return
class C { method m() { foo(1, 2); return 1; } }
=== B6: bare method call no return
class C { method m() { $self->bar(); return 1; } }
=== B7: bare unshift
class C { method m() { my @list = (); unshift @list, 1; return scalar @list; } }
=== B8: bare warn
class C { method m() { warn "hi"; return 1; } }
=== C1: simple reassignment
class C { method m() { my $x = 1; $x = 2; return $x; } }
=== C2: compound assignment
class C { method m() { my $x = 1; $x += 2; return $x; } }
=== C3: string concat assign
class C { method m() { my $s = "a"; $s .= "b"; return $s; } }
=== C4: array element assignment
class C { method m() { my @a = (1); $a[0] = 2; return $a[0]; } }
=== C5: hash element assignment
class C { method m() { my %h = (); $h{k} = 1; return $h{k}; } }
=== D1: if/else with reassignment
class C { method m($n) { my $x = 0; if ($n > 0) { $x = 1; } else { $x = 2; } return $x; } }
=== D2: while loop
class C { method m() { my $i = 0; while ($i < 3) { $i = $i + 1; } return $i; } }
=== D3: foreach loop
class C { method m() { my $sum = 0; foreach my $n (1, 2, 3) { $sum = $sum + $n; } return $sum; } }
=== D4: postfix if
class C { method m($n) { my $x = 0; $x = 1 if $n > 0; return $x; } }
=== D5: postfix while
class C { method m() { my $i = 0; $i = $i + 1 while $i < 3; return $i; } }
=== D6: ternary
class C { method m($n) { my $x = $n > 0 ? 1 : 2; return $x; } }
=== D7: nested if
class C { method m($n) { my $x = 0; if ($n > 0) { if ($n > 5) { $x = 1; } else { $x = 2; } } else { $x = 3; } return $x; } }
=== D8: try/catch
class C { method m() { try { die "boom"; } catch ($e) { return 0; } return 1; } }
=== E1: method with no return (implicit)
class C { method m() { my $x = 1; $x } }
=== E2: explicit return in branch
class C { method m($n) { if ($n > 0) { return 1; } return 0; } }
=== E3: return from inside loop
class C { method m() { foreach my $n (1, 2, 3) { return $n if $n == 2; } return 0; } }
=== E4: die from inside method
class C { method m() { die "no" if 1; return 1; } }
=== F1: method call with chain
class C { method m() { return $self->foo->bar; } }
=== F2: method call with args
class C { method m() { return $self->foo(1, 2, 3); } }
=== F3: function call with capture
class C { method m() { my $r = foo(1, 2); return $r; } }
=== G1: postfix deref array
class C { method m() { my $r = [1, 2]; return $r->@*; } }
=== G2: postfix deref hash
class C { method m() { my $r = { a => 1 }; return $r->%*; } }
=== G3: subscript array
class C { method m() { my @a = (1, 2); return $a[0]; } }
=== G4: subscript hash
class C { method m() { my %h = (k => 1); return $h{k}; } }
=== H1: map block
class C { method m() { my @r = map { $_ * 2 } (1, 2, 3); return scalar @r; } }
=== H2: grep block
class C { method m() { my @r = grep { $_ > 1 } (1, 2, 3); return scalar @r; } }
=== H3: sort
class C { method m() { my @r = sort (3, 1, 2); return $r[0]; } }
=== H4: anonymous sub
class C { method m() { my $f = sub ($x) { return $x + 1; }; return $f->(1); } }
=== I1: ADJUST block
class C { field $x :param; ADJUST { $x = $x + 1; } method m() { return $x; } }
=== I2: top-level sub
sub greet ($name) { return "hi $name"; }
=== I3: my sub
class C { method m() { my sub helper ($n) { return $n * 2; } return helper(3); } }
=== J1: regex match
class C { method m($s) { return $s =~ /foo/; } }
=== J2: regex substitution
class C { method m($s) { $s =~ s/foo/bar/; return $s; } }
=== J3: qw literal
class C { method m() { my @keys = qw(a b c); return scalar @keys; } }
=== K1: pre-increment
class C { method m() { my $i = 0; ++$i; return $i; } }
=== K2: post-increment
class C { method m() { my $i = 0; $i++; return $i; } }
=== L1: logical and
class C { method m($a, $b) { return $a && $b; } }
=== L2: logical or
class C { method m($a, $b) { return $a || $b; } }
=== L3: defined-or
class C { method m($a, $b) { return $a // $b; } }
=== L4: not
class C { method m($a) { return !$a; } }
