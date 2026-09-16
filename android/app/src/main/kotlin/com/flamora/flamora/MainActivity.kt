package com.flamora.flamora

import com.ryanheise.audioservice.AudioServiceActivity

// Must extend AudioServiceActivity (not plain FlutterActivity): it serves
// audio_service's shared engine, otherwise AudioService.init fails with
// "wrong FlutterEngine" and Android playback can never start.
class MainActivity : AudioServiceActivity()
