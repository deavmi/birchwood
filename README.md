![](branding/logo_small.png)

# birchwood

## _A sane IRC framework for the D language_

> [13:51:00] <zh_> A sane IRC framework for the D language
>> [13:51:11] <zh_> s/sane/professional

![DUB](https://img.shields.io/dub/v/birchwood?color=%23c10000ff%20&style=flat-square) ![DUB](https://img.shields.io/dub/dt/birchwood?style=flat-square) ![DUB](https://img.shields.io/dub/l/birchwood?style=flat-square)

## Installation

To add birchwood to your project simply run:

```bash
dub add birchwood
```

### Dependencies

Birchwood depends on the following D libraries:

* `eventy` (at least 0.4.0)
* `dlog` (at least 0.3.19)

## Usage

You can take a look at the `Client` API documentation on [DUB](https://birchwood.dpldocs.info/birchwood.client.client.Client.html).

## Compatibility

- [x] [rfc1459](https://www.rfc-editor.org/rfc/rfc1459)
   * Supports all the numeric codes
- [x] [rfc2812](https://www.rfc-editor.org/rfc/rfc2812)
   * Supports all the numeric codes

More standards will be added within the next month or so, mostly relating to new response codes that just need to be added.

## Credits

* [supremestdoggo](https://github.com/supremestdoggo)
   * Adding IRC message formatting code (`267f8886150dbd40eb5c2fecb9d7e3a4c8dfd71f`)

## License

See [LICENSE](LICENSE).
