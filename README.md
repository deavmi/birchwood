<p align="center">
<img src="logo.png" width=220>
</p>

<br>

<h1 align="center">birchwood</h1>

<h3 align="center"><i><b>A sane IRC framework for the D language</i></b></h3>

---

<br>
<br>

```
[13:51:00] <zh_> A sane IRC framework for the D language
[13:51:11] <zh_> s/sane/professional
```

## Installation

To add birchwood to your project simply run:

```bash
dub add birchwood
```

### Dependencies

Birchwood dependends on the following D libraries:

* `libsnooze` (0.3.0)
* `eventy` (0.4.0)
* `dlog` (0.3.19)

## Usage

You can take a look at the `Client` API documentation on [DUB](https://birchwood.dpldocs.info/birchwood.client.Client.html).

## Compatibility

- [x] [rfc1459](https://www.rfc-editor.org/rfc/rfc1459)
   * Supports all the numeric codes
- [x] [rfc2812](https://www.rfc-editor.org/rfc/rfc2812)
   * Supports all the numeric codes

More standards will be added within the next month or so, mostly relating to new response codes that just need to be added.

## License

See [LICENSE](LICENSE).
