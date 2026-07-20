pin 'application-pallastrade-admin', to: 'pallastrade/admin/application.js', preload: false

pin "@hotwired/turbo-rails", to: "turbo.min.js"
pin "@hotwired/stimulus", to: "stimulus.min.js"
pin "@hotwired/stimulus-loading", to: "stimulus-loading.js"

pin '@rails/actioncable', to: 'actioncable.esm.js', preload: ['application-pallastrade-admin']
pin '@rails/activestorage', to: 'activestorage.esm.js', preload: ['application-pallastrade-admin']
pin '@rails/actiontext', to: '@rails--actiontext@7.2.201.js', preload: ['application-pallastrade-admin']
pin 'trix', to: 'trix@2.1.15.js', preload: ['application-pallastrade-admin']

pin 'sortablejs', preload: ['application-pallastrade-admin'] # @1.15.6
pin 'chartkick', to: 'chartkick.js', preload: ['application-pallastrade-admin']
pin 'Chart.bundle', to: 'Chart.bundle.js', preload: ['application-pallastrade-admin']
pin 'local-time', preload: ['application-pallastrade-admin'] # @3.0.2
pin 'mapkick/bundle', to: 'mapkick.bundle.js', preload: ['application-pallastrade-admin']
pin 'dompurify', preload: ['application-pallastrade-admin'] # @3.2.5

# Stimulus components
pin '@stimulus-components/rails-nested-form', to: '@stimulus-components--rails-nested-form.js', preload: ['application-pallastrade-admin'] # @5.0.0
pin 'stimulus-notification', preload: ['application-pallastrade-admin'] # @2.2.0
pin 'stimulus-password-visibility', preload: ['application-pallastrade-admin'] # @2.1.1
pin 'stimulus-sortable', preload: ['application-pallastrade-admin'] # @4.1.1
pin 'hotkeys-js', preload: ['application-pallastrade-admin'] # @3.13.9
pin 'stimulus-use', preload: ['application-pallastrade-admin'] # @0.51.3
pin 'stimulus-checkbox-select-all', preload: ['application-pallastrade-admin'] # @5.3.0
pin 'stimulus-clipboard', preload: ['application-pallastrade-admin'] # @4.0.1
pin "@stimulus-components/dialog", to: "@stimulus-components--dialog.js", preload: ['application-pallastrade-admin'] # @1.0.1

# We can't vendor some of the javascript libraries
# because they have relative imports in the code,
# and importmaps don't handle them, leaving us with broken imports.

# All the pins that are pinning to `ga.jspm.io`
# can be replaced with vendored versions
# after this PR: https://github.com/rails/importmap-rails/pull/235 is merged

# Uppy
pin '@uppy/core', to: 'https://ga.jspm.io/npm:@uppy/core@4.4.1/lib/index.js', preload: ['application-pallastrade-admin']
pin '@uppy/dashboard', to: 'https://ga.jspm.io/npm:@uppy/dashboard@4.3.1/lib/index.js', preload: ['application-pallastrade-admin']
pin '@uppy/image-editor', to: 'https://ga.jspm.io/npm:@uppy/image-editor@3.3.1/lib/index.js', preload: ['application-pallastrade-admin']
pin '@transloadit/prettier-bytes',
    to: 'https://ga.jspm.io/npm:@transloadit/prettier-bytes@0.3.5/dist/prettierBytes.js',
    preload: ['application-pallastrade-admin']
pin '@uppy/informer', to: 'https://ga.jspm.io/npm:@uppy/informer@4.2.1/lib/index.js', preload: ['application-pallastrade-admin']
pin '@uppy/provider-views', to: 'https://ga.jspm.io/npm:@uppy/provider-views@4.4.1/lib/index.js', preload: ['application-pallastrade-admin']
pin '@uppy/status-bar', to: 'https://ga.jspm.io/npm:@uppy/status-bar@4.1.1/lib/index.js', preload: ['application-pallastrade-admin']
pin '@uppy/store-default', to: 'https://ga.jspm.io/npm:@uppy/store-default@4.2.0/lib/index.js', preload: ['application-pallastrade-admin']
pin '@uppy/thumbnail-generator', to: 'https://ga.jspm.io/npm:@uppy/thumbnail-generator@4.1.1/lib/index.js', preload: ['application-pallastrade-admin']
pin '@uppy/utils/lib/FOCUSABLE_ELEMENTS', to: 'https://ga.jspm.io/npm:@uppy/utils@6.1.1/lib/FOCUSABLE_ELEMENTS.js',
                                          preload: ['application-pallastrade-admin']
pin '@uppy/utils/lib/Translator', to: 'https://ga.jspm.io/npm:@uppy/utils@6.1.1/lib/Translator.js', preload: ['application-pallastrade-admin']
pin '@uppy/utils/lib/VirtualList', to: 'https://ga.jspm.io/npm:@uppy/utils@6.1.1/lib/VirtualList.js', preload: ['application-pallastrade-admin']
pin '@uppy/utils/lib/dataURItoBlob', to: 'https://ga.jspm.io/npm:@uppy/utils@6.1.1/lib/dataURItoBlob.js', preload: ['application-pallastrade-admin']
pin '@uppy/utils/lib/emaFilter', to: 'https://ga.jspm.io/npm:@uppy/utils@6.1.1/lib/emaFilter.js', preload: ['application-pallastrade-admin']
pin '@uppy/utils/lib/findAllDOMElements',
    to: 'https://ga.jspm.io/npm:@uppy/utils@6.1.1/lib/findAllDOMElements.js',
    preload: ['application-pallastrade-admin']
pin '@uppy/utils/lib/findDOMElement', to: 'https://ga.jspm.io/npm:@uppy/utils@6.1.1/lib/findDOMElement.js', preload: ['application-pallastrade-admin']
pin '@uppy/utils/lib/generateFileID', to: 'https://ga.jspm.io/npm:@uppy/utils@6.1.1/lib/generateFileID.js', preload: ['application-pallastrade-admin']
pin '@uppy/utils/lib/getDroppedFiles',
    to: 'https://ga.jspm.io/npm:@uppy/utils@6.1.1/lib/getDroppedFiles/index.js',
    preload: ['application-pallastrade-admin']
pin '@uppy/utils/lib/getFileNameAndExtension',
    to: 'https://ga.jspm.io/npm:@uppy/utils@6.1.1/lib/getFileNameAndExtension.js',
    preload: ['application-pallastrade-admin']
pin '@uppy/utils/lib/getFileType', to: 'https://ga.jspm.io/npm:@uppy/utils@6.1.1/lib/getFileType.js', preload: ['application-pallastrade-admin']
pin '@uppy/utils/lib/getTextDirection', to: 'https://ga.jspm.io/npm:@uppy/utils@6.1.1/lib/getTextDirection.js', preload: ['application-pallastrade-admin']
pin '@uppy/utils/lib/getTimeStamp', to: 'https://ga.jspm.io/npm:@uppy/utils@6.1.1/lib/getTimeStamp.js', preload: ['application-pallastrade-admin']
pin '@uppy/utils/lib/isDragDropSupported',
    to: 'https://ga.jspm.io/npm:@uppy/utils@6.1.1/lib/isDragDropSupported.js',
    preload: ['application-pallastrade-admin']
pin '@uppy/utils/lib/isObjectURL', to: 'https://ga.jspm.io/npm:@uppy/utils@6.1.1/lib/isObjectURL.js', preload: ['application-pallastrade-admin']
pin '@uppy/utils/lib/isPreviewSupported',
    to: 'https://ga.jspm.io/npm:@uppy/utils@6.1.1/lib/isPreviewSupported.js',
    preload: ['application-pallastrade-admin']
pin '@uppy/utils/lib/prettyETA', to: 'https://ga.jspm.io/npm:@uppy/utils@6.1.1/lib/prettyETA.js', preload: ['application-pallastrade-admin']
pin '@uppy/utils/lib/remoteFileObjToLocal',
    to: 'https://ga.jspm.io/npm:@uppy/utils@6.1.1/lib/remoteFileObjToLocal.js',
    preload: ['application-pallastrade-admin']
pin '@uppy/utils/lib/toArray', to: 'https://ga.jspm.io/npm:@uppy/utils@6.1.1/lib/toArray.js', preload: ['application-pallastrade-admin']
pin '@uppy/utils/lib/truncateString', to: 'https://ga.jspm.io/npm:@uppy/utils@6.1.1/lib/truncateString.js', preload: ['application-pallastrade-admin']
pin 'classnames', to: 'https://ga.jspm.io/npm:classnames@2.5.1/index.js', preload: ['application-pallastrade-admin']
pin 'cropperjs', to: 'https://ga.jspm.io/npm:cropperjs@1.6.2/dist/cropper.js', preload: ['application-pallastrade-admin']
pin 'eventemitter3', to: 'https://ga.jspm.io/npm:eventemitter3@5.0.1/index.mjs', preload: ['application-pallastrade-admin']
pin 'exifr/dist/mini.esm.mjs', to: 'https://ga.jspm.io/npm:exifr@7.1.3/dist/mini.esm.mjs', preload: ['application-pallastrade-admin']
pin 'lodash/throttle.js', to: 'https://ga.jspm.io/npm:lodash@4.17.21/throttle.js', preload: ['application-pallastrade-admin']
pin 'lodash/debounce.js', to: 'https://ga.jspm.io/npm:lodash@4.17.21/debounce.js', preload: ['application-pallastrade-admin']
pin 'lodash/merge.js', to: 'https://ga.jspm.io/npm:lodash@4.17.21/merge.js', preload: ['application-pallastrade-admin']
pin 'memoize-one', to: 'https://ga.jspm.io/npm:memoize-one@6.0.0/dist/memoize-one.esm.js', preload: ['application-pallastrade-admin']
pin 'mime-match', to: 'https://ga.jspm.io/npm:mime-match@1.0.2/index.js', preload: ['application-pallastrade-admin']
pin 'namespace-emitter', to: 'https://ga.jspm.io/npm:namespace-emitter@2.0.1/index.js', preload: ['application-pallastrade-admin']
pin 'nanoid/non-secure', to: 'https://ga.jspm.io/npm:nanoid@5.0.9/non-secure/index.js', preload: ['application-pallastrade-admin']
pin 'p-queue', to: 'https://ga.jspm.io/npm:p-queue@8.0.1/dist/index.js', preload: ['application-pallastrade-admin']
pin 'p-timeout', to: 'https://ga.jspm.io/npm:p-timeout@6.1.4/index.js', preload: ['application-pallastrade-admin']
pin 'preact', to: 'https://ga.jspm.io/npm:preact@10.25.4/dist/preact.module.js', preload: ['application-pallastrade-admin']
pin 'preact/hooks', to: 'https://ga.jspm.io/npm:preact@10.25.4/hooks/dist/hooks.module.js', preload: ['application-pallastrade-admin']
pin 'shallow-equal', to: 'https://ga.jspm.io/npm:shallow-equal@3.1.0/dist/index.modern.mjs', preload: ['application-pallastrade-admin']
pin 'wildcard', to: 'https://ga.jspm.io/npm:wildcard@1.1.2/index.js', preload: ['application-pallastrade-admin']
pin '@paralleldrive/cuid2', to: 'https://ga.jspm.io/npm:@paralleldrive/cuid2@2.2.2/index.js', preload: ['application-pallastrade-admin']
pin '@uppy/core/lib/BasePlugin.js', to: 'https://ga.jspm.io/npm:@uppy/core@4.4.1/lib/BasePlugin.js', preload: ['application-pallastrade-admin']
pin '@uppy/utils/lib/RateLimitedQueue', to: 'https://ga.jspm.io/npm:@uppy/utils@6.1.1/lib/RateLimitedQueue.js', preload: ['application-pallastrade-admin']
pin '@noble/hashes/crypto', to: 'https://ga.jspm.io/npm:@noble/hashes@1.7.1/crypto.js', preload: ['application-pallastrade-admin']
pin '@noble/hashes/sha3', to: 'https://ga.jspm.io/npm:@noble/hashes@1.7.1/sha3.js', preload: ['application-pallastrade-admin']

# Tom Select
pin 'tom-select/dist/esm/tom-select.complete.js',
    to: 'https://ga.jspm.io/npm:tom-select@2.4.1/dist/esm/tom-select.complete.js',
    preload: ['application-pallastrade-admin']
pin '@orchidjs/sifter', to: 'https://ga.jspm.io/npm:@orchidjs/sifter@1.1.0/dist/esm/sifter.js', preload: ['application-pallastrade-admin']
pin '@orchidjs/unicode-variants',
    to: 'https://ga.jspm.io/npm:@orchidjs/unicode-variants@1.1.2/dist/esm/index.js',
    preload: ['application-pallastrade-admin']

# Easepick
pin '@easepick/core',
    to: '@easepick--core.js',
    preload: ['application-pallastrade-admin'] # @1.2.1
pin '@easepick/preset-plugin',
    to: '@easepick--preset-plugin.js',
    preload: ['application-pallastrade-admin'] # @1.2.1
pin '@easepick/range-plugin',
    to: '@easepick--range-plugin.js',
    preload: ['application-pallastrade-admin'] # @1.2.1
pin '@easepick/base-plugin',
    to: '@easepick--base-plugin.js',
    preload: ['application-pallastrade-admin'] # @1.2.1
pin '@easepick/datetime',
    to: '@easepick--datetime.js',
    preload: ['application-pallastrade-admin'] # @1.2.1
#

pin '@simonwep/pickr',
    to: '@simonwep--pickr.js',
    preload: ['application-pallastrade-admin'] # @1.9.1

# floating-ui
pin "@floating-ui/dom", to: "@floating-ui--dom.js", preload: ['application-pallastrade-admin'] # @1.7.4
pin "@floating-ui/core", to: "@floating-ui--core.js", preload: ['application-pallastrade-admin'] # @1.7.3
pin "@floating-ui/utils", to: "@floating-ui--utils.js", preload: ['application-pallastrade-admin'] # @0.2.10
pin "@floating-ui/utils/dom", to: "@floating-ui--utils--dom.js", preload: ['application-pallastrade-admin'] # @0.2.10

# CodeMirror
pin "@codemirror/commands", to: "@codemirror--commands.js" # @6.9.0
pin "@codemirror/lang-json", to: "@codemirror--lang-json.js" # @6.0.2
pin "@codemirror/language", to: "@codemirror--language.js" # @6.11.3
pin "@codemirror/state", to: "@codemirror--state.js" # @6.5.2
pin "@codemirror/view", to: "@codemirror--view.js" # @6.38.4
pin "codemirror" # @6.0.2
pin "@codemirror/autocomplete", to: "@codemirror--autocomplete.js" # @6.19.0
pin "@codemirror/lint", to: "@codemirror--lint.js" # @6.9.0
pin "@codemirror/search", to: "@codemirror--search.js" # @6.5.11
pin "@lezer/common", to: "@lezer--common.js" # @1.2.3
pin "@lezer/highlight", to: "@lezer--highlight.js" # @1.2.1
pin "@lezer/json", to: "@lezer--json.js" # @1.0.3
pin "@lezer/lr", to: "@lezer--lr.js" # @1.4.2
pin "@marijn/find-cluster-break", to: "@marijn--find-cluster-break.js" # @1.0.2
pin "crelt" # @1.0.6
pin "style-mod" # @4.1.2
pin "w3c-keyname" # @2.2.8

# Highlight.js
pin "@highlightjs/cdn-assets/es/core.min.js", to: "@highlightjs--cdn-assets--es--core.min.js.js" # @11.11.1
pin "@highlightjs/cdn-assets/es/languages/json.min.js", to: "@highlightjs--cdn-assets--es--languages--json.min.js.js" # @11.11.1

pin_all_from PallasTrade::Admin::Engine.root.join('app/javascript/spree/admin/controllers'),
             under: 'pallastrade/admin/controllers',
             to: 'pallastrade/admin/controllers',
             preload: ['application-pallastrade-admin']
pin_all_from PallasTrade::Admin::Engine.root.join('app/javascript/spree/admin/helpers'),
             under: 'pallastrade/admin/helpers',
             to: 'pallastrade/admin/helpers',
             preload: ['application-pallastrade-admin']

draw PallasTrade::Core::Engine.root.join('config/importmap.rb')
