{
  "targets": [
    {
      "target_name": "superwrapper_pdf",
      "sources": [
        "src/lib.rs"
      ],
      "cflags": [
        "-fvisibility=hidden"
      ],
      "defines": [
        "NAPI_DISABLE_CPP_EXCEPTIONS"
      ],
      "conditions": [
        ["OS=='mac'", {
          'xcode_settings': {
            'OTHER_CFLAGS': ['-fembed-bitcode-marker']
          }
        }]
      ]
    }
  ]
}