# ABOUTME: Doc-decay regression — asserts the MOP architecture doc exists and names every metaobject.
# ABOUTME: If MOP::Foo is added to lib/Chalk/MOP/, list it below so the doc keeps documenting it.
use 5.42.0;
use utf8;
use Test::More;

my $doc = 'docs/architecture/mop.md';

ok(-f $doc, "$doc exists") or BAIL_OUT("MOP architecture doc missing");

open my $fh, '<', $doc or BAIL_OUT("cannot read $doc: $!");
my $content = do { local $/; <$fh> };
close $fh;

my @required_types = qw(
    Chalk::MOP
    Chalk::MOP::Class
    Chalk::MOP::Method
    Chalk::MOP::Sub
    Chalk::MOP::Field
    Chalk::MOP::Import
    Chalk::MOP::Phaser
    Chalk::MOP::Phaser::Adjust
);

for my $type (@required_types) {
    like($content, qr/\Q$type\E/, "$doc mentions $type");
}

done_testing;
