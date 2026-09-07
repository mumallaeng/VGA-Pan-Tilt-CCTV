# 골든 모델 통합 검증 — 영상처리 파이프라인 (서보 입력 직전까지)

`top.sv` 의 영상처리 경로를, 카메라 프레임버퍼 이후 ~ `servo_top` 입력 직전까지
**소프트웨어 골든 모델과 bit-exact 로 동일함**을 증명한다. 육안 비교가 아니라
6개 단계 각각의 **SHA-256 이 완전히 일치**함을 보인다.

## 서사 (발표용)

1. `gmodel.py` — 영상처리 알고리즘의 **참조 구현**(골든 모델). 순수 표준
   라이브러리 Python. 임의의 320x240 입력 이미지에 대해 녹색 검출 → 3x3
   정리 → 바운딩박스 → 박스 그린 결과 이미지를 계산한다.
2. `tb_top_video_golden.sv` — `top.sv` 와 **동일하게 결선한** RTL 통합
   하네스. 같은 입력 이미지에 대해 같은 결과를 계산한다.
3. `compare.py` — 두 결과의 6개 단계 산출물을 SHA-256 으로 대조.
   전 단계 일치 → **HW 구현이 골든 모델과 완전히 동등함**이 증명됨.

## 검증 대상 경로

```
frame_buffer(RGB565)           <- $readmemh 이미지 메모리로 대체
  -> vga_frame_reader_v4        MODE_FULLSCREEN(vga_sw=2'b01), RGB565 스트림 + RGB444 + box_en 오버레이
  -> green_color_filter         녹색 마스크 (G_MIN=128, GR_DIFF=GB_DIFF=40)
  -> noise_filter_3x3           3x3 다수결(>=5), line_buffer(제로패딩)
  -> centroid_filter            min_max_find -> object_center -> center_error
  -> draw_box                   THICKNESS=2, done 에서 min/max 래치
  -> (display_control 패스스루)  최종 화면 RGB = reader vga_r/g/b (box burn-in)
```

`servo_top` 은 포함하지 않는다. 경계 신호(`frame_dx/frame_dy/frame_valid`)를
단계 5로 캡처한다.

`display_control`/`rgb_out_reg` 은 non-split·`red_filter_en=0` 에서 단순
패스스루(+1클럭 지연)이므로 하네스에서 인스턴스화하지 않고 `vga_r/g/b` 를
직접 캡처한다. split 모드 / `red_filter_en=1`(이진 마스크 뷰) / `h_sync`·
`v_sync` CDC 정렬은 v1 범위 밖 (화소값이 아니라 디스플레이 타이밍).

## 파일

| 파일 | 실행 위치 | 내용 |
|---|---|---|
| `make_synth_ppm.py` | any (stdlib) | 음영 있는 녹색 공 + OV7670식 열화(RGB565/노이즈/비네팅) 320x240 P6 생성. 공 전체 green 검출 보장 |
| `img2hex.py` | any (stdlib) | 320x240 P6 PPM → RGB565 `.hex` (`$readmemh` 용, `r>>3 g>>2 b>>3`) |
| `gmodel.py` | any (stdlib) | 파이프라인의 사이클 충실 Python 포트 → `golden_*` 산출물 6종 |
| `tb_top_video_golden.sv` | iverilog / xsim | RTL 통합 하네스 → `rtl_*` 산출물 6종 |
| `compare.py` | any (stdlib) | 6쌍 SHA-256 대조표, 첫 불일치 좌표, `diff_out.ppm` |
| `setup_env.bat` | Windows | 이 폴더에 `.venv` 만들고 Pillow+numpy 설치 (`--force` 로 재생성) |
| `png2ppm.py` | PIL 필요 | 임의 이미지(PNG 등) → 320x240 P6 PPM (사진 반입용) |
| `ppm2png.py` | PIL 필요 | 결과 PPM → 보기용 PNG (발표 자료용) |
| `run_local.sh` | macOS/Linux (iverilog 13) | 빌드+시뮬+골든+대조 일괄 |
| `run_remote.bat` | Windows (Vivado 2020.2) | 위와 동일, xsim 사용. `.venv` 있으면 자동 사용 |

핵심 흐름(`img2hex.py`/`gmodel.py`/`compare.py`)은 표준 라이브러리만 쓰므로
시스템 Python 으로 그냥 돌아간다. **PNG 등 사진을 직접 넣으려면** Pillow 가
필요한데, 원격 Windows Python 3.14 에는 PIL/numpy 가 없으므로 먼저 한 번:

```
cd tb\golden_model
setup_env.bat
```

가 `.venv` 를 만들고 Pillow+numpy 를 설치한다. 이후 `run_remote.bat` 는
`.venv` 를 자동 감지해 사용하고, `.ppm` 이 아닌 인자를 주면 `png2ppm.py` 로
먼저 320x240 P6 로 변환한다. (`.venv` 는 `.gitignore` 처리됨.)

## 실행

### 로컬 (bit-exact 등가성 확인, iverilog)

```
cd tb/golden_model
./run_local.sh                 # 합성 이미지
./run_local.sh path/to/pic.ppm # 지정 이미지 (320x240 P6)
```

### 원격 (Vivado 2020.2 xsim, 발표 근거)

```
cd tb\golden_model
run_remote.bat
run_remote.bat greenball_320x240.ppm
```

두 경로 모두 마지막에 `compare.py` 표를 출력한다. 6/6 `MATCH` →
`RESULT: TEST PASSED`.

## top.sv 최소 패치 (detection decimation)

`rtl/top/top.sv` 에 ~20줄 추가 (`tb/golden_model/patch_top.py` 가 in-place 적용,
`--revert` 로 되돌림. **커밋 안 함**):

```
+ reg det_phase;
+ always_ff @(posedge vga_pclk or posedge rst)
+     det_phase <= (vga_sw == 2'b01) ? (~x_pixel[0] & ~y_pixel[0]) : 1'b1;
+ wire det_valid = red_valid & det_phase;
  noise_filter_3x3 U_NOISE_FILTER ( ... .red_valid(det_valid) ...);  // was red_valid
```

FULLSCREEN 에서 소스 픽셀당 첫 replica 만 검출 파이프라인에 통과시킨다.
디스플레이·`draw_box` 는 그대로 640×480 2×. 다른 `vga_sw` 모드는 이미 1:1 →
`det_phase` 항상 1 (게이트 투명).

## 세 가지 config + 파일명 태그

`run_remote.bat` / `run_local.sh` 는 **세 config 를 모두** 돌리고 산출물
파일명에 태그를 붙여 한 폴더(`_work\`)에 공존시킨다:

| 태그 | 조건 | 결과 |
|---|---|---|
| `_640x480` | FULLSCREEN + 패치 게이트 | **의도한 파이프라인.** 검출 1:1 정상, 640×480 출력, 박스 공에 그려짐 |
| `_640x480_raw` | FULLSCREEN, 게이트 off (`+RAW=1`) | 패치 전 동작. 2× 스트림 → 노이즈 생존 → 박스 벌어짐 |
| `_320x240` | MODE_ORIGINAL (`+FS=0`) | 검출 1:1 정상, 320×240 출력. 단 `draw_box` `x_pixel[9:1]` 반감이라 박스 미표시 |

## 산출물 6종 (× 3 config 태그)

| # | `rtl_*_<tag>` / `golden_*_<tag>` | 포맷 | 의미 |
|---|---|---|---|
| 1 | `fb565_<tag>.hex` | 76800 x 4hex | 로드된 프레임버퍼 (sanity) |
| 2 | `green_<tag>.pgm` | P5 320x240 | `green_color_filter` 마스크 |
| 3 | `clean_<tag>.pgm` | P5 320x240 | `noise_filter_3x3` 마스크 |
| 4 | `bbox_<tag>.txt` | `min_x max_x min_y max_y target_valid` | `centroid_filter` @ `done` |
| 5 | `preservo_<tag>.txt` | `frame_dx frame_dy frame_valid` | 서보 입력 경계 @ `done` |
| 6 | `out_<tag>.ppm` | P6 640x480 | 최종 화면 RGB (박스 burn-in) |

한 모드만 돌리려면: `+FS=1`(또는 `0`), `+TAG=<이름>` plusarg 를 xsim/vvp 에
직접 넘긴다. `gmodel.py <hex> <dir> <FS> <TAG>`, `compare.py <dir> <TAG>`.

## 라스터 / 캡처 규약 (양측 동일)

- 3프레임 연속 스윕. pass 0 이 `centroid_filter` 를 채우고, pass 1 은 pass 0 의
  `done` 으로 `draw_box` 가 이미 래치된 **정상 상태** — 캡처는 pass 1.
  (단일 프레임만 돌리면 `draw_box` 가 비어 박스가 안 그려짐: `done` 은 프레임
  끝에서야 오므로.)
- `noise_filter_3x3` `line_buffer` 와 `rows_seen` 은 프레임 간 유지되므로 pass 1
  이 이미 정상 상태. (pass 0 만 워밍업 게이트 + 콜드 버퍼로 상단 2줄이 다름.)

## 알려진 특성 (검증이 드러낸 것, 버그 아님/RTL 그대로)

- **FULLSCREEN 2배 스트림**: `vga_frame_reader_v4.pixel_valid` 는 640x480 전
  픽셀에서 high 이고 `top.sv` 는 이 doubled 스트림(`img_x`=0,0,1,1,…)을 그대로
  검출 파이프라인에 넣는다. `line_buffer` 깊이는 소스 폭(320)이라 한 소스 행이
  두 디스플레이 행에 걸쳐 두 번 기록되고, 그 결과 `buf1`≈`buf2` 로 수직
  윈도우가 겹친다. **단일 밝은-녹색 스트레이 픽셀이 3x3 을 통과**할 수 있다
  (x 방향 2배 + 수직 중복). 이전 세션에서 사용자가 본 "박스가 프레임마다
  튄다" 와 직결되는 특성. 골든 모델은 이 동작을 **그대로** 재현한다(그래서
  해시가 일치). 검출 안정화는 별도 과제 — 이전 세션 진단(EMA/연결요소/CDC)
  참조.
- **`min_max_find` frame_end 경계**: `(clean_x==318)&&(clean_y==238)` 에서
  커밋 트리거("Need to fix after line buffer is fixed" 주석). 마지막 행/열은
  트리거에서 빠진다. 포트도 동일.
- **`MIN_RED_COUNT=10`** 은 전역 카운트 게이트일 뿐 공간 응집 조건 없음.

## 해시 매니페스트 (공식 데모 입력)

```
공식 데모 입력: golden_test_sample_img.png
  sha256 89029a314dd7cba5e1a9b609dbd385f2aca6a0cd005e73d37c1d2e7af1bca1b3
  1448x1086 실사진, 초록 공만 검출 RGB 범위로 리컬러(그늘면 포함 공 전체가
  g8>=128 & g8-r8>=40 & g8-b8>=40 만족). 배경/빵판/전선/바닥 초록 반점은 그대로.
  png2ppm.py 가 320x240 nearest-neighbor 로 축소 -> img2hex.py 로 RGB565 .hex.
날짜: 2026-09-07
검증: iverilog 13.0 (macOS) == Vivado 2020.2 xsim (remote) == gmodel.py  -- 세 config 모두 6/6 bit-identical
공통(세 config): fb565 775e641b6a46...  green 7b7ea18dc5c4...

[_640x480]      FULLSCREEN + 패치 게이트   bbox = 173 227 69 123 1   preservo = 40 24 1   (의도한 파이프라인: 공 전체 박스)
  clean_640x480.pgm     e82bfd1834a81c5a6141b72fc220d9e8d16587638f140e81c566c7910ace07fa
  bbox_640x480.txt      677ff721d8af21427f8e709ca1850422da6963b16ed0f3d9f3633ad5ca7496ef
  preservo_640x480.txt  039cb1f560d94d76dbbb2b83b9e3588d837079cea35b9d30b5bfc7b8edaebae9
  out_640x480.ppm       608ebb2597e368ca38d52b9581857a248ed027f97195c9586d0226511846e886

[_640x480_raw]  FULLSCREEN, 게이트 off     bbox = 44 301 68 221 1   preservo = 12 -24 1   (패치 전: 바닥 반점에 벌어짐)
  clean_640x480_raw.pgm 040a1cd0781d527be777b3435a2564a27bc83aa848ea08d6afac3ab2e4601bc5
  bbox_640x480_raw.txt  d7bdfed14d0df1a7103e0ccec47344718286ed7d0cb8f61c1837d80513fe3746
  out_640x480_raw.ppm   813c1e3000e1337095ce3d4ef525e786d5e1e0d7e42756d9dade0cbce1cb32e2

[_320x240]      MODE_ORIGINAL 1:1          bbox = 173 227 69 123 1   preservo = 40 24 1
  clean_320x240.pgm     e82bfd1834a81c5a6141b72fc220d9e8d16587638f140e81c566c7910ace07fa
  out_320x240.ppm       7a609d1629e308ef8ee36281543ee5e7420ec3d323ae08989626c261f6273c45
```

> - **패치 후 `_640x480` = `_320x240` 검출 결과** (`clean`/`bbox` 해시 동일,
>   bbox `173 227 69 123` = 공 전체 54x54) + 640x480 출력 + 박스 표시.
> - `_640x480_raw` 는 바닥 초록 반점이 2x 스트림에서 3x3 통과 -> bbox
>   `44 301 68 221` 로 벌어짐. 패치가 이걸 제거함.
> - green 마스크는 세 config 해시 동일 - 색 판정은 해상도 무관.
> - `_320x240` 은 `draw_box` `x_pixel[9:1]` 반감이라 박스가 부분/오프셋 표시.
>   실사용 모드는 FULLSCREEN.
> - 각 config 마다 `render_images.py` 가 뷰용 PNG 생성:
>   `golden_*` = SW 골든 모델, `rtl_*` = SV(iverilog/xsim). `_work\` 참조.

## 실제 사진 반입

```
cd tb\golden_model
setup_env.bat                       :: 최초 1회 (.venv + Pillow/numpy)
run_remote.bat path\to\photo.png    :: png2ppm -> img2hex -> xsim -> golden -> compare
```

그다음 `.venv\Scripts\python.exe ppm2png.py _work\rtl_out.ppm rtl_out.png`,
`... _work\golden_out.ppm golden_out.png` 로 발표용 PNG 를 뽑고, `compare.py`
출력의 SHA-256 6줄을 위 매니페스트에 그 사진 기준으로 고정한다.
